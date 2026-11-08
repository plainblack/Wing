use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Wing;
use Wing::Web;
use Wing::Web::Account;
use Plack::Test;
use Dancer::Handler;
use HTTP::Request::Common;

set show_errors => 0;
set logger => 'null';
set public => $ENV{WING_HOME}.'/public';
set views => $ENV{WING_HOME}.'/var/init/views';
set engines => {template_toolkit => {start_tag => '[%', end_tag => '%]'}};
set template => 'template_toolkit';

my $user = Wing->db->resultset('User')->create({username => 'account-owner', email => 'account-owner@example.invalid'});
my $key = $user->apikeys->create({name => 'account-client'});
my %session;
for my $name (qw(denied viewer editor admin)) {
    my $owner = $name eq 'admin'
        ? Wing->db->resultset('User')->create({username => 'account-admin', email => 'account-admin@example.invalid', admin => 1})
        : $user;
    $owner->mark_secondary_auth_verified;
    my $client = $owner->apikeys->create({name => 'client-'.$name});
    my $permissions = $name eq 'viewer' ? ['view_my_account']
        : $name eq 'editor' ? ['view_my_account', 'edit_my_account'] : [];
    for my $permission (@$permissions) {
        Wing->db->resultset('APIKeyPermission')->create({user_id => $owner->id, api_key_id => $client->id, permission => $permission});
    }
    $session{$name} = $owner->start_session({sso => 1, api_key_id => $client->id});
}
my $sso_session = $session{editor};

test_psgi(Dancer::Handler->get_handler->psgi_app, sub {
    my $request = shift;
    my $authorization = Wing::SSO->new(db => Wing->db, api_key_id => $key->id,
        user_id => $user->id, postback_uri => 'native', requested_permissions => ['edit_my_account'])->store;
    my %needs = (denied => {}, viewer => {view_my_account => 1},
        editor => {view_my_account => 1, edit_my_account => 1}, admin => {view_my_account => 1, edit_my_account => 1});
    for my $name (sort keys %session) {
        for my $transport (qw(cookie parameter)) {
            my $doomed = $user->apikeys->create({name => 'doomed-'.$name.'-'.$transport});
            for my $route (
                ['GET', '/account', 'view_my_account', 200], ['POST', '/account', 'edit_my_account', 302],
                ['GET', '/account/apikeys', 'view_my_account', 200],
                ['GET', '/account/apikeys/'.$key->id, 'view_my_account', 200],
                ['POST', '/account/apikey', 'edit_my_account', 302],
                ['POST', '/account/apikey/'.$key->id, 'edit_my_account', 302],
                ['DELETE', '/account/apikey/'.$doomed->id, 'edit_my_account', 302],
                ['POST', '/account/deactivate', 'edit_my_account', 441],
                ['GET', '/account/verify/secondary/auth', 'edit_my_account', 428],
                ['GET', '/sso/success?sso_id='.$authorization->id, 'view_my_account', 200],
                ['GET', '/account/facebook/postback?code=test-code'],
                ['GET', '/sso?api_key_id='.$key->id.'&postback_uri=native&permission=edit_my_account'],
                ['GET', '/sso/authorize?sso_id='.$authorization->id],
                ['POST', '/sso/authorize?sso_id='.$authorization->id],
            ) {
                my ($method, $path, $permission, $allowed) = @$route;
                my $http = HTTP::Request->new($method, 'http://localhost'.$path);
                if ($transport eq 'cookie') {
                    $http->header(Cookie => 'session_id='.$session{$name}->id);
                } else {
                    $http->uri->query_form($http->uri->query_form, session_id => $session{$name}->id);
                }
                my $response = $request->($http);
                unlike $response->header('Set-Cookie') || '', qr/session_id=/, "$name via $transport: $method $path issues no site session";
                if (defined $permission && $needs{$name}{$permission}) {
                    is $response->code, $allowed, "$name via $transport: $method $path is allowed with $permission";
                } else {
                    is $response->code, 450, "$name via $transport: $method $path is refused";
                }
            }
        }
    }
    is_deeply [sort @{$session{$_}->get_permissions}], [sort keys %{$needs{$_}}],
        "$_ SSO client cannot grant itself permissions" for qw(denied viewer editor);
    is_deeply $session{admin}->get_permissions, [], 'admin SSO client cannot grant itself permissions';
    my $stranger = Wing->db->resultset('User')->create({username => 'account-stranger', email => 'account-stranger@example.invalid'});
    is $request->(POST 'http://localhost/sso/authorize', Cookie => 'session_id='.$stranger->start_session({sso => 0})->id,
        Content => [sso_id => $authorization->id])->code, 401, 'another user cannot approve an authorization request';
    is_deeply(Wing::SSO->new(id => $authorization->id, db => Wing->db)->get_permissions, [],
        'refused approval grants nothing');
    for my $path ('/account', '/account/apikeys', '/sso/authorize?sso_id='.$authorization->id) {
        is $request->(GET 'http://localhost'.$path)->code, 401, "$path requires authentication";
    }
    is $request->(GET 'http://localhost/sso?api_key_id='.$key->id.'&postback_uri=native&permission=edit_my_account')->code,
        200, 'anonymous application authorization displays login';
    {
        local Wing->config->config->{facebook} = {app_id => 'test-app', secret => 'test-secret', postback => 'http://localhost/account/facebook/postback'};
        # Facebook is the external boundary; sessions, routing and account changes remain real.
        no warnings 'redefine';
        my $oauth_requests = 0;
        local *Facebook::OpenGraph::get_user_token_by_code = sub { $oauth_requests++; return {access_token => 'test-oauth-token'} };
        local *Facebook::OpenGraph::fetch = sub { return {id => '123456789', name => 'External User'} };
        my $callback = $request->(GET 'http://localhost/account/facebook/postback?code=test-code',
            Cookie => 'session_id='.$sso_session->id);
        is $callback->code, 450, 'Facebook account linking refuses SSO credentials';
        unlike $callback->header('Set-Cookie') || '', qr/session_id=/, 'Facebook callback cannot mint a site session from SSO';
        is $oauth_requests, 0, 'SSO callback is refused before external OAuth requests';
        my $site_callback = $request->(GET 'http://localhost/account/facebook/postback?code=test-code',
            Cookie => 'session_id='.$user->start_session({sso => 0})->id);
        is $site_callback->code, 302, 'site session can link a Facebook account';
        like $site_callback->header('Set-Cookie') || '', qr/session_id=/, 'site Facebook callback retains login';
    }
    Wing::Session->add_validator(sub { ($_[0]->auth_source // '') ne 'revoked-by-app' });
    for my $reason (qw(expired password app-rejected)) {
        my $invalid_user = Wing->db->resultset('User')->new({username => 'invalid-'.$reason, email => 'invalid-'.$reason.'@example.invalid'});
        $invalid_user->encrypt_and_set_password('initial-password');
        $invalid_user->insert;
        my $invalid = $invalid_user->start_session({sso => 1, api_key_id => $key->id});
        if ($reason ne 'password') {
            my $data = Wing->cache->get($invalid->key);
            if ($reason eq 'expired') {
                $data->{absolute_expires_at} = 1;
            } else {
                $data->{auth_source} = 'revoked-by-app';
            }
            Wing->cache->set($invalid->key, $data);
        }
        if ($reason eq 'password') {
            $invalid_user->encrypt_and_set_password('replacement-password');
            $invalid_user->update;
        }
        is $request->(GET 'http://localhost/account', Cookie => 'session_id='.$invalid->id)->code,
            401, "$reason SSO session is logged out before checking the credential type";
        is $request->(GET 'http://localhost/sso?api_key_id='.$key->id.'&postback_uri=native&permission=edit_my_account',
            Cookie => 'session_id='.$invalid->id)->code, 200, "$reason SSO session can reauthenticate";
    }
    my $site = $user->start_session({sso => 0});
    my $cookie = 'session_id='.$site->id;
    is $request->(POST 'http://localhost/account/apikey', Cookie => $cookie, Content => [name => 'site-created-key'])->code,
        302, 'site session can create an API key';
    my $created = $user->apikeys->find({name => 'site-created-key'});
    ok $created, 'site-created API key exists';
    my $key_page = $request->(GET 'http://localhost/account/apikeys/'.$created->id, Cookie => $cookie);
    is $key_page->code, 200, 'site session can view the API key';
    like $key_page->content, qr/site-created-key/, 'real account template includes the created key';
    is $request->(POST 'http://localhost/account/apikey/'.$created->id, Cookie => $cookie, Content => [name => 'site-updated-key'])->code,
        302, 'site session can update an API key';
    is $request->(HTTP::Request->new('DELETE', 'http://localhost/account/apikey/'.$created->id, [Cookie => $cookie]))->code,
        302, 'site session can delete an API key';
    my $update = $request->(POST 'http://localhost/account', Cookie => $cookie, Content => [real_name => 'Site Owner']);
    is $update->code, 302, 'site session can save account settings';
    like $update->header('Set-Cookie') || '', qr/session_id=/, 'site settings retain login refresh';
    my $begin = $request->(GET 'http://localhost/sso?api_key_id='.$key->id.'&postback_uri=native&permission=edit_my_account', Cookie => $cookie);
    is $begin->code, 302, 'site session can begin authorizing an application';
    my ($sso_id) = $begin->header('Location') =~ /sso_id=([^&]+)/;
    ok $sso_id, 'site session receives an authorization request';
    is $request->(GET 'http://localhost/sso/authorize?sso_id='.$sso_id, Cookie => $cookie)->code,
        200, 'site session can view the consent page';
    is $request->(POST 'http://localhost/sso/authorize', Cookie => $cookie, Content => [sso_id => $sso_id])->code,
        302, 'site session can approve application permissions';
    is_deeply(Wing::SSO->new(id => $sso_id, db => Wing->db)->get_permissions, ['edit_my_account'],
        'approval grants the requested permission');
    is $request->(GET 'http://localhost/sso/success?sso_id='.$sso_id, Cookie => $cookie)->code,
        200, 'site session can see application authorization success';
});

done_testing;

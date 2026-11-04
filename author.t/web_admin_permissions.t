use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Wing;
use Wing::Web;
use Wing::Web::Admin::User;
use Wing::Web::Account;
use Wing::Web::Admin::Trends;
use Wing::Web::Admin::Wingman;
use Plack::Test;
use Dancer::Handler;
use HTTP::Request::Common;

set show_errors => 0;
set logger => 'null';
set public => $ENV{WING_HOME}.'/public';
set views => $ENV{WING_HOME}.'/var/init/views';
set engines => {template_toolkit => {start_tag => '[%', end_tag => '%]'}};
set template => 'template_toolkit';
my $admin = Wing->db->resultset('User')->create({username => 'admin-owner', email => 'admin-owner@example.invalid', admin => 1});
my $target = Wing->db->resultset('User')->new({username => 'admin-target', email => 'admin-target@example.invalid'});
$target->encrypt_and_set_password('target-original');
$target->insert;
my $key = $admin->apikeys->create({name => 'admin-client'});
my $sso = $admin->start_session({sso => 1, api_key_id => $key->id});
test_psgi(Dancer::Handler->get_handler->psgi_app, sub {
    my $request = shift;
    for my $permission (undef, 'edit_my_account') {
        if (defined $permission) {
            Wing->db->resultset('APIKeyPermission')->create({user_id => $admin->id, api_key_id => $key->id, permission => $permission});
        }
        for my $transport (qw(cookie parameter)) {
            for my $route (
                ['GET', '/admin/users'], ['POST', '/admin/user'],
                ['GET', '/admin/user/'.$target->id], ['POST', '/admin/user/'.$target->id],
                ['POST', '/admin/user/'.$target->id.'/become'],
                ['GET', '/admin/trends/reports'], ['GET', '/admin/trends/reports/manage'],
                ['GET', '/admin/wingman'], ['GET', '/admin/wingman/tubes/default'], ['GET', '/admin/wingman/jobs/1'],
            ) {
                my $http = HTTP::Request->new($route->[0], 'http://localhost'.$route->[1]);
                if ($transport eq 'cookie') {
                    $http->header(Cookie => 'session_id='.$sso->id);
                } else {
                    $http->uri->query_form(session_id => $sso->id);
                }
                my $response = $request->($http);
                is $response->code, 450, "$transport: @$route refuses admin SSO with ".($permission || 'no permissions');
                unlike $response->header('Set-Cookie') || '', qr/session_id=/, 'admin SSO cannot mint a site session';
            }
        }
    }

    my $attempt = $request->(POST 'http://localhost/admin/user/'.$target->id, Cookie => 'session_id='.$sso->id,
        Content => [username => $target->username, email => $target->email, password1 => 'compromised', password2 => 'compromised']);
    is $attempt->code, 450, 'SSO cannot change a user password';
    is $request->(POST 'http://localhost/login', Content => [login => $target->username, password => 'target-original'])->code,
        302, 'refused SSO edit leaves the original password usable';
    ok !$target->has_secondary_auth_token, 'refused impersonation does not mark the target verified';
    for my $cookie ('', 'session_id=invalid-session-id', 'session_id='.$target->start_session({sso => 0})->id) {
        is $request->(GET 'http://localhost/admin/users', Cookie => $cookie)->code,
            $cookie =~ /invalid/ || $cookie eq '' ? 401 : 450, 'admin routes require a valid administrator';
    }
    my $expired = $admin->start_session({sso => 1, api_key_id => $key->id});
    my $data = Wing->cache->get($expired->key);
    $data->{absolute_expires_at} = 1;
    Wing->cache->set($expired->key, $data);
    is $request->(GET 'http://localhost/admin/users', Cookie => 'session_id='.$expired->id)->code,
        401, 'expired admin SSO is treated as logged out';
    my $site = $admin->start_session({sso => 0});
    my $cookie = 'session_id='.$site->id;
    for my $path ('/admin/users', '/admin/user/'.$target->id, '/admin/trends/reports', '/admin/trends/reports/manage',
        '/admin/wingman', '/admin/wingman/tubes/default') {
        is $request->(GET 'http://localhost'.$path, Cookie => $cookie)->code, 200, "$path accepts an admin site session";
    }
    is $request->(POST 'http://localhost/admin/user', Cookie => $cookie,
        Content => [username => 'site-admin-created', email => 'site-admin-created@example.invalid'])->code,
        302, 'admin site session can create a user';
    is $request->(POST 'http://localhost/admin/user/'.$target->id, Cookie => $cookie,
        Content => [username => $target->username, email => $target->email, password1 => 'site-updated', password2 => 'site-updated'])->code,
        302, 'admin site session can edit a user password';
    is $request->(POST 'http://localhost/login', Content => [login => $target->username, password => 'site-updated'])->code,
        302, 'admin password edit persists';
    my $deactivated = Wing->db->resultset('User')->create({username => 'deactivated-target',
        email => 'deactivated-target@example.invalid', permanently_deactivated => 1});
    my $retained_admin = $admin->start_session({sso => 0});
    my $failed = $request->(POST 'http://localhost/admin/user/'.$deactivated->id.'/become',
        Cookie => 'session_id='.$retained_admin->id);
    is $failed->code, 442, 'a deactivated target cannot be impersonated';
    unlike $failed->header('Set-Cookie') || '', qr/session_id=/, 'failed impersonation issues no replacement session';
    is $request->(GET 'http://localhost/admin/users', Cookie => 'session_id='.$retained_admin->id)->code,
        200, 'failed impersonation preserves the administrator login';

    set behind_proxy => 0;
    for my $case (
        ['direct peer', undef, '127.0.0.1'],
        ['empty header', '', '127.0.0.1'],
        ['all empty entries', " , \t, ", '127.0.0.1'],
        ['single address', '198.51.100.7', '198.51.100.7'],
        ['multiple hops', '203.0.113.4, 198.51.100.7', '198.51.100.7'],
        ['whitespace and trailing empty entries', " \t203.0.113.4 , 198.51.100.7\t, , ", '198.51.100.7'],
        ['spoofed first address before trusted final address', '192.0.2.9, 203.0.113.33', '203.0.113.33'],
    ) {
        my ($name, $header, $expected) = @$case;
        my $admin_session = $admin->start_session({sso => 0});
        my $http = POST 'http://localhost/admin/user/'.$target->id.'/become', Cookie => 'session_id='.$admin_session->id;
        $http->header('X-Real-IP' => $header) if defined $header;
        my $become = $request->($http);
        is $become->code, 302, "$name: admin site session can impersonate a user";
        my ($session_id) = ($become->header('Set-Cookie') || '') =~ /session_id=([^;]+)/;
        ok $session_id, "$name: impersonation issues a session";
        is $request->(GET 'http://localhost/admin/users', Cookie => 'session_id='.$admin_session->id)->code,
            401, "$name: successful impersonation ends the previous administrator session";
        my $impersonation = Wing::Session->new(id => $session_id, db => Wing->db);
        is $impersonation->user_id, $target->id, "$name: new session belongs to the target user";
        is $impersonation->ip_address, $expected, "$name: session records one normalized client address";
        is(Wing->db->resultset('User')->find($target->id)->last_ip, $expected,
            "$name: target's stored last_ip uses that same address");
    }

});
done_testing;

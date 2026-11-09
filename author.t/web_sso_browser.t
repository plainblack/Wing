use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Wing;
use Wing::Web;
use Wing::Web::Account;
use Wing::SSO;
use Plack::Test;
use Dancer::Handler;
use HTTP::Request::Common;

set show_errors => 0;
set logger => 'null';
set public => $ENV{WING_HOME}.'/public';
set views => $ENV{WING_HOME}.'/var/init/views';
set engines => {template_toolkit => {start_tag => '[%', end_tag => '%]'}};
set template => 'template_toolkit';

my $owner = Wing->db->resultset('User')->create({username => 'sso-key-owner', email => 'sso-key-owner@example.invalid'});
my $key = $owner->apikeys->create({name => 'sso-browser-client'});
my $visitor = Wing->db->resultset('User')->new({username => 'sso-visitor', email => 'sso-visitor@example.invalid'});
$visitor->encrypt_and_set_password('visitor-password');
$visitor->insert;
Wing->db->resultset('APIKeyPermission')->create({user_id => $visitor->id, api_key_id => $key->id, permission => 'view_my_account'});
my $postback = 'https://client.example.invalid/back';

sub token { Wing::SSO->new(id => $_[0], db => Wing->db) }

test_psgi(Dancer::Handler->get_handler->psgi_app, sub {
    my $request = shift;
    my $start = sub {
        my $response = $request->(GET 'http://localhost/sso?api_key_id='.$key->id.'&postback_uri='.$postback, @_);
        my ($id) = $response->content =~ /name="sso_id" value="([^"]+)"/;
        my ($browser) = ($response->header('Set-Cookie') // '') =~ /\bsso_browser=([^;]+)/;
        return ($id, $browser, scalar $response->header('Set-Cookie'));
    };
    my $login = sub {
        my ($sso_id, @cookie) = @_;
        $request->(POST 'http://localhost/login', @cookie, Content => [login => 'sso-visitor', password => 'visitor-password', sso_id => $sso_id]);
    };

    my ($stolen, $attacker, $attacker_cookie) = $start->();
    ok $stolen, 'GET /sso shows a signed-out visitor the login form with an sso_id';
    ok $attacker, 'GET /sso binds the sso_id to the browser with a cookie';
    like $attacker_cookie, qr/HttpOnly/i, 'the sso_browser cookie is HttpOnly';
    unlike $attacker_cookie, qr/\Q$stolen\E/, 'the cookie does not hold the sso_id the key owner receives';

    my $original_facebook = Wing->config->get('facebook');
    Wing->config->set('facebook', {app_id => 'sso-browser-app', secret => 'sso-browser-secret', postback => 'http://localhost/account/facebook/postback'});
    my $facebook = $request->(GET 'http://localhost/account/facebook?sso_id='.$stolen);
    # Config::JSON writes set() to the config file, so put the real block back.
    defined $original_facebook ? Wing->config->set('facebook', $original_facebook) : Wing->config->delete('facebook');
    is $facebook->code, 302, '/account/facebook redirects to Facebook';
    unlike $facebook->header('Set-Cookie') // '', qr/\bsso_/, '/account/facebook sets no SSO cookie from the query';

    for my $cookie ([], [Cookie => 'sso_id='.$stolen], [Cookie => 'sso_browser=forged']) {
        my $refused = $login->($stolen, @$cookie);
        is $refused->code, 401, "login with an sso_id this browser did not start is refused (@$cookie)";
        unlike $refused->header('Set-Cookie') // '', qr/\bsession_id=/, "the refused login starts no session (@$cookie)";
        ok !defined token($stolen)->user_id, "the refused login does not bind the visitor to the token (@$cookie)";
    }
    my $wrong_password = $request->(POST 'http://localhost/login', Content => [login => 'sso-visitor', password => 'wrong', sso_id => $stolen]);
    is $wrong_password->code, 401, 'the refusal comes before the password check, so it does not reveal whether the password was right';

    my $created = $request->(POST 'http://localhost/account/create', Content => [username => 'sso-created', email => 'sso-created@example.invalid', password1 => 'created-password', password2 => 'created-password', sso_id => $stolen]);
    is $created->code, 401, 'account creation with an sso_id this browser did not start is refused';
    ok !Wing->db->resultset('User')->search({username => 'sso-created'})->count, 'the refused account creation stores no user';

    my ($first, $browser) = $start->();
    my ($second, $kept) = $start->(Cookie => 'sso_browser='.$browser);
    ok !defined $kept || $kept eq $browser, 'a second GET /sso keeps the browser cookie';
    is $login->($stolen, Cookie => 'sso_browser='.$browser)->code, 401, "login with another browser's sso_id is refused";
    my $accepted = $login->($first, Cookie => 'sso_browser='.$browser);
    is $accepted->header('Location'), $postback.'?sso_id='.$first, 'the first SSO flow in a browser still finishes after a second one starts';
    is token($first)->user_id, $visitor->id, 'that login binds the visitor to the token';
    ok token($first)->consented, 'that login approves the token for a key the visitor approved';
    is $login->($second, Cookie => 'sso_browser='.$browser)->header('Location'), $postback.'?sso_id='.$second, 'the second SSO flow finishes too';
});

done_testing;

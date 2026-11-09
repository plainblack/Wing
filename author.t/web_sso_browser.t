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
        my $response = $request->(GET 'http://localhost/sso?api_key_id='.$key->id.'&postback_uri='.$postback);
        my ($id) = $response->content =~ /name="sso_id" value="([^"]+)"/;
        return ($id, scalar $response->header('Set-Cookie'));
    };
    my $login = sub {
        my ($sso_id, @cookie) = @_;
        $request->(POST 'http://localhost/login', @cookie, Content => [login => 'sso-visitor', password => 'visitor-password', sso_id => $sso_id]);
    };

    my ($stolen, $attacker_cookie) = $start->();
    ok $stolen, 'GET /sso shows a signed-out visitor the login form with an sso_id';
    like $attacker_cookie, qr/\bsso_id=\Q$stolen\E;/, 'GET /sso binds the sso_id to the browser with a cookie';
    like $attacker_cookie, qr/HttpOnly/i, 'the sso_id cookie is HttpOnly';

    my $original_facebook = Wing->config->get('facebook');
    Wing->config->set('facebook', {app_id => 'sso-browser-app', secret => 'sso-browser-secret', postback => 'http://localhost/account/facebook/postback'});
    my $facebook = $request->(GET 'http://localhost/account/facebook?sso_id='.$stolen);
    # Config::JSON writes set() to the config file, so put the real block back.
    defined $original_facebook ? Wing->config->set('facebook', $original_facebook) : Wing->config->delete('facebook');
    is $facebook->code, 302, '/account/facebook redirects to Facebook';
    unlike $facebook->header('Set-Cookie') // '', qr/\bsso_id=/, '/account/facebook does not set an sso_id cookie from the query';

    my $refused = $login->($stolen);
    is $refused->code, 401, 'login with an sso_id this browser did not start is refused';
    unlike $refused->header('Set-Cookie') // '', qr/\bsession_id=/, 'the refused login starts no session';
    ok !defined token($stolen)->user_id, 'the refused login does not bind the visitor to the token';

    my ($own) = $start->();
    is $login->($stolen, Cookie => 'sso_id='.$own)->code, 401, 'login with an sso_id other than the one this browser started is refused';
    ok !defined token($stolen)->user_id, 'that login does not bind the visitor to the token either';

    my $accepted = $login->($own, Cookie => 'sso_id='.$own);
    is $accepted->header('Location'), $postback.'?sso_id='.$own, 'login with the sso_id this browser started goes to the postback';
    is token($own)->user_id, $visitor->id, 'that login binds the visitor to the token';
    ok token($own)->consented, 'that login approves the token for a key the visitor approved';
});

done_testing;

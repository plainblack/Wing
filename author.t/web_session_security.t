use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Wing;
use Wing::Web;
use Wing::Web::Account;
use Wing::Web::Admin::User;
use Plack::Test;
use Dancer::Handler;
use HTTP::Request::Common;

set show_errors => 0;
set template => 'template_toolkit';
set views => $ENV{WING_HOME}.'/author.t/tenant_files/views';
my $user = Wing->db->resultset('User')->new({username => 'origin-user'});
$user->encrypt_and_set_password('origin-password');
$user->insert;
my $code = $user->generate_password_reset_code;
my $app = Dancer::Handler->get_handler->psgi_app;
test_psgi $app, sub {
    my $request = shift;
    for my $headers ([Origin => 'https://app.example'], [Origin => 'null'], ['Sec-Fetch-Site' => 'cross-site']) {
        my $login = $request->(POST 'http://localhost/login', @$headers,
            Content => [login => $user->username, password => 'origin-password']);
        is $login->code, 302, "login with @$headers succeeds";
        like $login->header('Set-Cookie'), qr/session_id=/, 'login issues a session';
    }
    for my $headers ([], [Origin => 'http://LOCALHOST:80'], ['Sec-Fetch-Site' => 'same-origin']) {
        my $res = $request->(POST 'http://localhost/login', @$headers,
            Content => [login => $user->username, password => 'origin-password']);
        is $res->code, 302, 'headerless and same-origin HTTP login survive';
        like $res->header('Set-Cookie'), qr/SameSite=Lax/, 'HTTP cookie has SameSite';
        unlike $res->header('Set-Cookie'), qr/; Secure/i, 'HTTP cookie is usable on HTTP';
        unlike $res->header('Set-Cookie'), qr/HttpOnly/i, 'JavaScript compatibility retained';
        like $res->header('Set-Cookie'), qr/path=\/; expires=/, 'root path and expiry retained';
    }
    for my $proxy (0, 1) {
        set behind_proxy => $proxy;
        my $res = $request->(POST 'http://localhost/login', 'X-Forwarded-Proto' => 'https',
            Content => [login => $user->username, password => 'origin-password']);
        is $res->code, 302, 'login succeeds';
        is !!($res->header('Set-Cookie') =~ /; Secure/i), !!$proxy, 'forwarded HTTPS trusted only behind_proxy';
    }
    set behind_proxy => 0;
    my $key = $user->apikeys->create({name => 'origin-sso'});
    my $sso = Wing::SSO->new(db => Wing->db, api_key_id => $key->id,
        postback_uri => 'native', requested_permissions => [''])->store;
    my $sso_login = $request->(POST 'http://localhost/login', Origin => 'https://app.example',
        Content => [login => $user->username, password => 'origin-password', sso_id => $sso->id]);
    is $sso_login->code, 302, 'SSO login still redirects';
    is(Wing::SSO->new(db => Wing->db, id => $sso->id)->user_id, $user->id,
        'SSO login associates authenticated user');
    my $created = $request->(POST 'http://localhost/account/create', Origin => 'https://app.example',
        Content => [username => 'origin-created', email => 'origin-created@example.invalid', password1 => 'created-password', password2 => 'created-password']);
    is $created->code, 302, 'cross-origin account creation succeeds';
    my $created_login = $request->(POST 'http://localhost/login', Content => [login => 'origin-created', password => 'created-password']);
    is $created_login->code, 302, 'newly created account can log in';
    my $reset = $request->(POST 'http://localhost/account/reset-password-code', Origin => 'https://app.example',
        Content => [code => $code, password1 => 'reset-password', password2 => 'reset-password']);
    is $reset->code, 302, 'cross-origin password reset establishes session';
    my $reset_login = $request->(POST 'http://localhost/login', Content => [login => $user->username, password => 'reset-password']);
    is $reset_login->code, 302, 'reset password persists and can log in';
    my $allowed = $request->(POST 'https://localhost/login',
        Content => [login => $user->username, password => 'reset-password']);
    is $allowed->code, 302, 'HTTPS login succeeds';
    like $allowed->header('Set-Cookie'), qr/SameSite=Lax/, 'session cookie has SameSite=Lax';
    like $allowed->header('Set-Cookie'), qr/; Secure(?:;|$)/i, 'native HTTPS session cookie is Secure';

    my $admin = Wing->db->resultset('User')->create({username => 'cookie-admin', email => 'cookie-admin@example.invalid', admin => 1});
    for my $scheme ('http', 'https') {
        my $session = $admin->start_session({ip_address => '127.0.0.1'});
        my $res = $request->(POST "$scheme://localhost/admin/user/".$user->id.'/become',
            Cookie => 'session_id='.$session->id);
        is $res->code, 302, 'admin impersonation still succeeds';
        my $cookie = $res->header('Set-Cookie') || '';
        like $cookie, qr/SameSite=Lax/, 'admin session cookie is Lax';
        is !!($cookie =~ /; Secure/i), !!($scheme eq 'https'), 'admin cookie follows HTTPS';
        unlike $cookie, qr/HttpOnly/i, 'admin cookie JavaScript compatibility retained';
    }
};
done_testing;

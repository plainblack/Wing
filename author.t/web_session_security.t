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
my $queries = 0;
Wing->db->storage->debugcb(sub { $queries++ });
Wing->db->storage->debug(1);
my $app = Dancer::Handler->get_handler->psgi_app;
test_psgi $app, sub {
    my $request = shift;
    my $cache_lookups = 0;
    my $cache_get = CHI::Driver->can('get');
    no warnings qw(redefine once);
    local *CHI::Driver::get = sub {
        $cache_lookups++ if $_[1] =~ /^password_reset/;
        return $cache_get->(@_);
    };
    for my $path ('/login', '/account/create', '/account/reset-password-code', '/account') {
        for my $headers (
            [Origin => 'http://localhost', Origin => 'http://evil.example'],
            [Origin => 'http://evil.example'], [Origin => 'null'], [Origin => ''],
            [Origin => 'http://localhost.evil.example'], [Origin => 'http://localhost@evil.example'],
            [Origin => 'http://evil.example@localhost'], [Origin => 'http://localhost/path'],
            [Origin => 'http://localhost?query'], [Origin => 'http://localhost#fragment'],
            [Origin => 'http://localhost:bad'], [Origin => 'http://localhost:65536'],
            [Origin => 'http://localhost:81'], [Origin => 'https://localhost'],
            [Origin => 'http://localhost\\evil.example'], [Origin => 'http://local%68ost'],
            [Origin => 'http://localhost http://evil.example'], [Origin => 'http://[invalid]'],
            ['Sec-Fetch-Site' => 'cross-site'],
            [Origin => 'http://localhost', 'Sec-Fetch-Site' => 'cross-site'],
        ) {
            my $before = $queries;
            my $cache_before = $cache_lookups;
            my $res = $request->(POST 'http://localhost'.$path, @$headers, Content => [
                login => $user->username, password => 'origin-password', username => 'hostile-create',
                code => $code, password1 => 'changed-password', password2 => 'changed-password']);
            is $res->code, 403, "$path refuses @$headers";
            is $queries, $before, 'refused before any SQL lookup or mutation';
            is $cache_lookups, $cache_before, 'refused before reset cache lookup';
            unlike $res->header('Set-Cookie') || '', qr/session_id=/, 'no session issued';
            like $res->content, qr/same.origin/i, 'actionable refusal in production mode';
        }
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
            Origin => ($proxy ? 'https' : 'http').'://localhost',
            Content => [login => $user->username, password => 'origin-password']);
        is $res->code, 302, 'effective scheme used for origin';
        is !!($res->header('Set-Cookie') =~ /; Secure/i), !!$proxy, 'forwarded HTTPS trusted only behind_proxy';
    }
    set behind_proxy => 1;
    my $proxied = $request->(POST 'http://internal/login',
        'X-Forwarded-Proto' => 'https', 'X-Forwarded-Host' => 'public.example:8443',
        Origin => 'https://public.example:8443',
        Content => [login => $user->username, password => 'origin-password']);
    is $proxied->code, 302, 'trusted proxy public host and nonstandard port work';
    set behind_proxy => 0;
    my $spoofed = $request->(POST 'http://localhost/login',
        'X-Forwarded-Host' => 'evil.example', Origin => 'http://evil.example',
        Content => [login => $user->username, password => 'origin-password']);
    is $spoofed->code, 403, 'forwarded host cannot override direct request origin';
    my $ipv6 = $request->(POST 'http://[::1]:8080/login', Host => '[::1]:8080', Origin => 'http://[::1]:8080',
        Content => [login => $user->username, password => 'origin-password']);
    is $ipv6->code, 302, 'same-origin IPv6 and explicit port login works';
    my $key = $user->apikeys->create({name => 'origin-sso'});
    my $sso = Wing::SSO->new(db => Wing->db, api_key_id => $key->id,
        postback_uri => 'native', requested_permissions => [''])->store;
    my $sso_login = $request->(POST 'http://localhost/login', Origin => 'http://localhost',
        Content => [login => $user->username, password => 'origin-password', sso_id => $sso->id]);
    is $sso_login->code, 302, 'same-origin SSO login still redirects';
    is(Wing::SSO->new(db => Wing->db, id => $sso->id)->user_id, $user->id,
        'SSO login associates authenticated user');
    my $created = $request->(POST 'http://localhost/account/create', Origin => 'http://localhost',
        Content => [username => 'origin-created', email => 'origin-created@example.invalid', password1 => 'created-password', password2 => 'created-password']);
    is $created->code, 302, 'same-origin account creation succeeds';
    my $created_login = $request->(POST 'http://localhost/login', Content => [login => 'origin-created', password => 'created-password']);
    is $created_login->code, 302, 'newly created account can log in';
    my $reset = $request->(POST 'http://localhost/account/reset-password-code', Origin => 'http://localhost',
        Content => [code => $code, password1 => 'reset-password', password2 => 'reset-password']);
    is $reset->code, 302, 'same-origin password reset establishes session';
    my $reset_login = $request->(POST 'http://localhost/login', Content => [login => $user->username, password => 'reset-password']);
    is $reset_login->code, 302, 'reset password persists and can log in';
    my $allowed = $request->(POST 'https://localhost/login', Origin => 'https://localhost',
        Content => [login => $user->username, password => 'reset-password']);
    is $allowed->code, 302, 'same-origin HTTPS login succeeds';
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
    my $res = $request->(POST 'http://localhost/login', Origin => 'http://evil.example',
        Content => [login => $user->username, password => 'origin-password']);
    is $res->code, 403, 'cross-origin login refused';
    unlike $res->header('Set-Cookie') || '', qr/session_id=/, 'refused login sets no session';
    like $res->content, qr/same.origin/i, 'refusal explains how to submit safely';
};
done_testing;

use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Wing;
use Wing::Rest;
use Wing::Rest::Session;
use Plack::Test;
use Dancer::Handler;
use HTTP::Request::Common;
my $user = Wing->db->resultset('User')->new({username => 'cookie-developer', developer => 1});
$user->encrypt_and_set_password('cookie-password');
$user->insert;
my $key = $user->apikeys->create({name => 'cookie-key'});
my $app = Dancer::Handler->get_handler->psgi_app;
test_psgi $app, sub {
    my $request = shift;
    for my $case (['http', 0, undef, 0], ['https', 0, undef, 1], ['http', 0, 'https', 0], ['http', 1, 'https', 1]) {
        my ($scheme, $proxy, $forwarded, $secure) = @$case;
        set behind_proxy => $proxy;
        my $res = $request->(POST "$scheme://localhost/api/session",
            (defined $forwarded ? ('X-Forwarded-Proto' => $forwarded) : ()),
            Content => [username => $user->username, password => 'cookie-password', api_key_id => $key->id]);
        is $res->code, 200, 'REST credential login succeeds';
        my $cookie = $res->header('Set-Cookie') || '';
        like $cookie, qr/session_id=.*path=\/api; expires=/, 'REST cookie preserves path and expiry';
        like $cookie, qr/SameSite=Lax/, 'REST cookie is Lax';
        is !!($cookie =~ /; Secure/i), !!$secure, 'REST cookie respects HTTPS trust';
        unlike $cookie, qr/HttpOnly/i, 'REST cookie remains available to JavaScript';
    }
};
done_testing;

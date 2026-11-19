use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Dancer::Test;
use Wing;
use Wing::Web;
use Wing::Web::Account;

set show_errors => 1;
my $user = Wing->db->resultset('User')->create({username => 'web-nested', email => 'web-nested@example.invalid'});
my $key = $user->apikeys->create({name => 'web-nested'});
my $session = $user->start_session({ip_address => '127.0.0.1', api_key_id => $key->id});
my $injection = {'= 0 OR 1=' => 'x'};

my $res = dancer_response POST => '/account/reset-password', {params => {login => $injection}};
is $res->status, 442, 'an object param is refused on a Wing::Web route';
like $res->content, qr/login/, 'the refusal names the login param';
$res = dancer_response POST => '/login', {params => {login => ['web-nested', 'web-nested@example.invalid'], password => 'x'}};
is $res->status, 442, 'login refuses a list of logins';

{
    # Wing's own call sites must stay safe even when the hook is not there.
    local Dancer::Factory::Hook->instance->hooks->{before} = [];
    $res = dancer_response POST => '/account/reset-password', {params => {login => $injection}};
    is $res->status, 442, 'password reset refuses an object login without the hook';
    $res = dancer_response POST => '/login', {params => {login => $injection, password => 'x'}};
    is $res->status, 442, 'login refuses an object login without the hook';
    $res = dancer_response GET => '/sso', {params => {session_id => $session->id, api_key_id => $injection, postback_uri => 'native'}};
    is $res->status, 442, 'SSO refuses an object api_key_id without the hook' or diag $res->content;
}

done_testing;

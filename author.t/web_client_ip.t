use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Dancer::Test;
use Wing;
use Wing::Web;
use Wing::Web::Account;
use Wing::SSO;

set show_errors => 1;
my $user = Wing->db->resultset('User')->create({username => 'web-address-test'});
my $key = $user->apikeys->create({name => 'web-address-test'});
my $session = $user->start_session({ip_address => '192.0.2.9', api_key_id => $key->id});
local $ENV{REMOTE_ADDR} = '192.0.2.9';
local $ENV{HTTP_X_REAL_IP} = '198.51.100.7';
my $res = dancer_response GET => '/sso', {
    params => {session_id => $session->id, api_key_id => $key->id, postback_uri => 'native', permission => ''},
};
diag $res->content if $res->status != 302;
is $res->status, 302, 'authenticated web SSO request redirects';
my ($id) = $res->header('Location') =~ /sso_id=([^&]+)/;
ok $id, 'redirect identifies the stored SSO token';
is(Wing::SSO->new(id => $id, db => Wing->db)->ip_address, '198.51.100.7',
    'web SSO creation stores the X-Real-IP address using the shared keyword');

done_testing;

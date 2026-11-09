use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer;
use Dancer::Test;
use Wing;
use Wing::Rest;
use Wing::Rest::Session;
use Wing::SSO;
use Plack::Test;
use Dancer::Handler;
use HTTP::Request::Common;

{
    package AddressGatedUser;
    use parent 'TestWing::DB::Result::User';
    sub describe {
        my ($self, %options) = @_;
        my $out = $self->SUPER::describe(%options);
        $out->{facility_access} = 1 if $options{ip_address} eq '198.51.100.7';
        return $out;
    }
}

my $user = Wing->db->resultset('User')->new({username => 'address-test', email => 'address-test@example.invalid', developer => 1});
$user->encrypt_and_set_password('address-test-password');
$user->insert;
my $key = $user->apikeys->create({name => 'address-test'});
my $users = Wing->db->resultset('User')->search({id => $user->id}, {result_class => 'AddressGatedUser'});
get '/address/describe' => sub { return describe($users->single) };
get '/address/list' => sub { return format_list($users, object_options => {}) };
get '/address/login' => sub { return login($user) };

get '/address/params' => sub { return expanded_params() };

sub response {
    my ($method, $path, $header, $params) = @_;
    local $ENV{REMOTE_ADDR} = '192.0.2.9';
    local $ENV{HTTP_X_REAL_IP};
    if (defined $header) { $ENV{HTTP_X_REAL_IP} = $header }
    else { delete $ENV{HTTP_X_REAL_IP} }
    my $res = dancer_response $method => $path, {
        headers => defined $header ? ['X-Real-IP' => $header] : [],
        params => $params || {},
    };
    diag $res->content if $res->status != 200;
    is $res->status, 200, "$method $path succeeds";
    return from_json($res->content)->{result};
}

for my $case (
    ['198.51.100.7', '198.51.100.7'],
    ['203.0.113.4, 198.51.100.7', '203.0.113.4, 198.51.100.7'],
    ['', '192.0.2.9'],
    [undef, '192.0.2.9'],
) {
    is response('GET', '/address/params', $case->[0])->{ipaddress}, $case->[1],
        'expanded parameters contain the X-Real-IP value or the direct peer';
}

my $address = '198.51.100.7';
is response('GET', '/address/describe', $address)->{facility_access}, 1,
    'describe receives the facility address for its field gate';
is response('GET', '/address/list', $address)->{items}[0]{facility_access}, 1,
    'real result set propagates the facility address into object descriptions';

ok !response('GET', '/address/describe', '203.0.113.4, 198.51.100.7')->{facility_access},
    'a forwarding chain is not one address and cannot open the gate';

my $app = Dancer::Handler->get_handler->psgi_app;
test_psgi $app, sub {
    my $request = shift;
    my $res = $request->(GET 'http://localhost/address/login', 'X-Real-IP' => $address);
    is $res->code, 302, 'real PSGI login request redirects';
    my ($id) = $res->header('Set-Cookie') =~ /session_id=([^;]+)/;
    ok $id, 'login sets a session cookie';
    is(Wing::Session->new(id => $id, db => Wing->db)->ip_address, '198.51.100.7',
        'login persists one address in the real session cache');
};
my $session = response('POST', '/api/session', $address, {
    username => $user->username, password => 'address-test-password', api_key_id => $key->id,
});
is(Wing::Session->new(id => $session->{id}, db => Wing->db)->ip_address, '198.51.100.7',
    'REST password login persists one address');
my $sso = Wing::SSO->new(db => Wing->db, api_key_id => $key->id, user_id => $user->id)->consent;
my $sso_session = response('POST', '/api/session/sso/'.$sso->id, $address,
    {private_key => $key->private_key});
is(Wing::Session->new(id => $sso_session->{id}, db => Wing->db)->ip_address, '198.51.100.7',
    'REST SSO exchange persists one address');

done_testing;

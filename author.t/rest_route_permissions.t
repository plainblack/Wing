use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Wing;
use Wing::Rest;
use Wing::DB::ResultSet;
use Plack::Test;
use Dancer::Handler;
use HTTP::Request::Common qw(GET);
use JSON qw(decode_json);

set show_errors => 0;
my $original_tenants = Wing->config->get('tenants');
Wing->config->delete('tenants');
require Wing::Rest::User;
require Wing::Rest::APIKey;
Wing->config->set('tenants', $original_tenants) if defined $original_tenants;

Wing->db->source($_)->resultset_class("Wing::DB::ResultSet") for qw(User APIKey APIKeyPermission);
my $user = Wing->db->resultset('User')->create({username => 'route-owner', email => 'route-owner@example.invalid'});
my $denied_key = $user->apikeys->create({name => 'route-denied-key'});
my $allowed_key = $user->apikeys->create({name => 'route-allowed-key'});
Wing->db->resultset('APIKeyPermission')->create({user_id => $user->id, api_key_id => $allowed_key->id, permission => 'view_my_account'});
my %session = (
    denied  => $user->start_session({sso => 1, api_key_id => $denied_key->id})->id,
    allowed => $user->start_session({sso => 1, api_key_id => $allowed_key->id})->id,
    site    => $user->start_session({sso => 0})->id,
);
my $private = qr/"(?:email|private_key|reason|permission)"\s*:/;
my @owned = ('/api/user/'.$user->id.'/apikeys', '/api/user/'.$user->id.'/apikeypermissions', '/api/apikey/'.$denied_key->id);
my @self = ('/api/user/whoami', '/api/user?query=route-owner');

test_psgi(Dancer::Handler->get_handler->psgi_app, sub {
    my $request = shift;
    my $get = sub {
        my ($path, $name) = @_;
        return $request->(GET 'http://localhost'.$path, (defined $name ? (Cookie => 'session_id='.$session{$name}) : ()));
    };
    for my $path (@owned) {
        my $response = $get->($path);
        is $response->code, 200, "$path stays public for anonymous clients";
        unlike $response->content, $private, "$path hides private fields from anonymous clients";
    }
    for my $path (@self) {
        is $get->($path)->code, 441, "$path still requires a session";
    }
    for my $path (@owned, @self) {
        my $response = $get->($path, 'denied');
        is $response->code, 200, "$path succeeds for an SSO owner without view_my_account";
        like $response->content, qr/"id"\s*:/, "$path keeps public identity for the denied owner";
        unlike $response->content, $private, "$path hides private fields without view_my_account";
        for my $name (qw(allowed site)) {
            my $authorized = $get->($path, $name);
            is $authorized->code, 200, "$path succeeds for the $name owner";
            like $authorized->content, $private, "$path shows private fields to the $name owner";
        }
    }
    is decode_json($get->('/api/user/whoami', 'denied')->content)->{result}{id}, $user->id, 'whoami identifies the denied SSO user';
});

done_testing;

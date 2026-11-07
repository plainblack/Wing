use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Wing;
use Wing::Rest;
use Plack::Test;
use Dancer::Handler;
use HTTP::Request::Common qw(GET);
use JSON qw(decode_json);
use Crypt::PK::RSA;
use Crypt::JWT qw(decode_jwt);

set show_errors => 0;
require Wing::Rest::User;
require Wing::Rest::APIKey;

my $user = Wing->db->resultset('User')->create({username => 'route-owner', email => 'route-owner@example.invalid'});
my $denied_key = $user->apikeys->create({name => 'route-denied-key'});
my $allowed_key = $user->apikeys->create({name => 'route-allowed-key'});
Wing->db->resultset('APIKeyPermission')->create({user_id => $user->id, api_key_id => $allowed_key->id, permission => 'view_my_account'});
my $editor_key = $user->apikeys->create({name => 'route-editor-key'});
Wing->db->resultset('APIKeyPermission')->create({user_id => $user->id, api_key_id => $editor_key->id, permission => 'edit_my_account'});
my %session = (
    denied  => $user->start_session({sso => 1, api_key_id => $denied_key->id})->id,
    allowed => $user->start_session({sso => 1, api_key_id => $allowed_key->id})->id,
    editor  => $user->start_session({sso => 1, api_key_id => $editor_key->id})->id,
    site    => $user->start_session({sso => 0})->id,
);
# Applications grant non-admin privileges by extending can_edit.
my $meta = TestWing::DB::Result::User->meta;
$meta->make_mutable;
$meta->add_around_method_modifier(can_edit => sub {
    my ($orig, $self, $viewer) = @_;
    return 1 if defined $viewer && $viewer->username eq 'route-manager';
    return $orig->($self, $viewer);
});
$meta->make_immutable(inline_constructor => 0);
my $manager = Wing->db->resultset('User')->create({username => 'route-manager'});
my $manager_key = $manager->apikeys->create({name => 'route-manager-key'});
my %manager_session = (
    denied => $manager->start_session({sso => 1, api_key_id => $manager_key->id})->id,
    site   => $manager->start_session({sso => 0})->id,
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
    my $renewals = sub { Wing->cache->get('session-'.$session{site})->{extended} };
    my $before = $renewals->();
    $get->('/api/user/whoami', 'site');
    is $renewals->(), $before + 1, 'whoami renews the session once';
    my %others = map { $_ => $request->(GET 'http://localhost/api/user-not-me?query=route-owner', Cookie => 'session_id='.$manager_session{$_}) } keys %manager_session;
    is $others{denied}->code, 200, 'user-not-me succeeds for a privileged SSO user without view_my_account';
    is decode_json($others{denied}->content)->{result}{items}[0]{id}, $user->id, 'user-not-me lists the other user';
    unlike $others{denied}->content, $private, 'user-not-me hides private fields without view_my_account';
    like $others{site}->content, $private, 'user-not-me shows private fields to a privileged site session';

    my $target = Wing->db->resultset('User')->create({username => 'route-target', email => 'hidden-target@example.invalid'});
    my $admin = Wing->db->resultset('User')->create({username => 'route-admin', email => 'route-admin@example.invalid', admin => 1});
    my $admin_session = $admin->start_session({sso => 0})->id;
    my $found = sub {
        my ($path, $session_id) = @_;
        return [map { $_->{id} } @{decode_json($request->(GET 'http://localhost'.$path, Cookie => 'session_id='.$session_id)->content)->{result}{items}}];
    };
    for my $route (qw(user user-not-me)) {
        for my $name (qw(denied site)) {
            is_deeply $found->("/api/$route?query=hidden-target", $session{$name}), [], "$route does not match another user's email for a non-admin $name session";
        }
        is_deeply $found->("/api/$route?query=hidden-target", $admin_session), [$target->id], "$route matches email for an admin";
        is_deeply $found->("/api/$route?query=route-target", $session{site}), [$target->id], "$route still matches username for a non-admin";
    }

    my $rsa = Crypt::PK::RSA->new;
    $rsa->generate_key(256);
    my $original_firebase = Wing->config->get('firebase');
    Wing->config->set('firebase', {id => 'route-firebase', database => 'route-db', api_key => 'route-api-key', service_email => 'route@example.invalid', admin_key => $rsa->export_key_pem('private')});
    my $jwt_path = '/api/user/'.$user->id.'/firebase-jwt';
    is $get->($jwt_path)->code, 441, 'firebase-jwt requires a session';
    for my $name (qw(denied allowed)) {
        my $response = $get->($jwt_path, $name);
        is $response->code, 450, "firebase-jwt refuses the $name SSO owner without edit_my_account";
        unlike $response->content, qr/route-api-key|"jwt"/, "firebase-jwt issues no credential to the $name SSO owner";
    }
    for my $name (qw(editor site)) {
        my $response = $get->($jwt_path, $name);
        is $response->code, 200, "firebase-jwt succeeds for the $name owner";
        my $result = decode_json($response->content)->{result};
        is $result->{api_key}, 'route-api-key', "firebase-jwt returns the Firebase config to the $name owner";
        is decode_jwt(token => $result->{jwt}, key => \$rsa->export_key_pem('public'))->{uid}, $user->id, "firebase-jwt signs a token for the $name owner";
    }
    # Config::JSON writes set() to the config file, so put the real block back.
    defined $original_firebase ? Wing->config->set('firebase', $original_firebase) : Wing->config->delete('firebase');
});

done_testing;

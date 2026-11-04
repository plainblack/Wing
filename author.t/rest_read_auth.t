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
require Wing::Rest::Session;
Wing->config->set('tenants', $original_tenants) if defined $original_tenants;
my $user = Wing->db->resultset('User')->new({username => 'read-owner', email => 'read-owner@example.invalid'});
$user->encrypt_and_set_password('read-password');
$user->insert;
my $key = $user->apikeys->create({name => 'read-key'});
my $denied = $user->start_session({sso => 1, api_key_id => $key->id});
generate_relationship('ProtectedUser', 'apikeys', db_class_name => 'User', permissions => ['view_my_account']);
generate_relationship('GuardedUser', 'apikeys', db_class_name => 'User', permissions => ['view_my_account'], verify_user => 'verify_is_admin');
generate_read('ProtectedUser', db_class_name => 'User', permissions => ['view_my_account']);
get '/anonymous-description' => sub { return describe($user, current_user => undef) };
Wing->db->source($_)->resultset_class('Wing::DB::ResultSet') for qw(User APIKey);
get '/anonymous-list' => sub {
    my $users = Wing->db->resultset('User')->search({id => $user->id});
    return format_list($users, current_user => undef, object_options => {});
};
my $allowed_key = $user->apikeys->create({name => 'allowed-read-key'});
Wing->db->resultset('APIKeyPermission')->create({user_id => $user->id, api_key_id => $allowed_key->id, permission => 'view_my_account'});
my $allowed = $user->start_session({sso => 1, api_key_id => $allowed_key->id});
my $expired = $user->start_session({sso => 1, api_key_id => $allowed_key->id});
Wing->cache->expire($expired->key);
for my $spec (['EmptyUser', []], ['UndefinedUser', undef]) {
    generate_read($spec->[0], db_class_name => 'User', permissions => $spec->[1]);
}
generate_read('PublicUser', db_class_name => 'User');
generate_read('ProtectedKey', db_class_name => 'APIKey', permissions => ['view_my_account']);
generate_relationship('ProtectedKey', 'user', db_class_name => 'APIKey', permissions => ['view_my_account']);
generate_relationship('PublicKey', 'user', db_class_name => 'APIKey');
generate_relationship('PublicUser', 'apikeys', db_class_name => 'User');
get '/implicit-description' => sub { return describe($user) };
get '/implicit-list' => sub {
    my $users = Wing->db->resultset('User')->search({id => $user->id});
    return format_list($users);
};
my $limited_user = Wing->db->resultset('User')->create({username => 'read-limited'});
my $limited = $limited_user->start_session({sso => 0});
Wing->cache->set('rpc_count_'.$_.$limited_user->id, 1000) for 0..59;
my $app = Dancer::Handler->get_handler->psgi_app;
test_psgi $app, sub {
    my $request = shift;
    for my $path ('/api/user/'.$user->id, '/api/protecteduser/'.$user->id.'/apikeys', '/api/protectedkey/'.$key->id.'/user') {
        my $response = $request->(GET 'http://localhost'.$path, Cookie => 'session_id='.$limited->id);
        is $response->code, 452, 'generated read propagates rate limit';
        is decode_json($response->content)->{error}{message}, 'Slow down! You are only allowed to make (30) requests per minute to the server.', 'original rate limit message';
    }
    my $res = $request->(GET 'http://localhost/api/protecteduser/'.$user->id, Cookie => 'session_id='.$denied->id);
    is $res->code, 200, 'owning SSO user without permission receives public profile';
    my $data = decode_json($res->content);
    is $data->{result}{id}, $user->id, 'public identity remains available';
    ok !exists $data->{result}{email}, 'denied permission cannot expose owner email';
    for my $session (undef, $denied->id) {
        my $response = $request->(GET 'http://localhost/api/user/'.$user->id,
            (defined $session ? (Cookie => 'session_id='.$session) : ()));
        is $response->code, 200, 'builtin public profile succeeds without permission';
        my $profile = decode_json($response->content)->{result};
        is $profile->{id}, $user->id, 'builtin public profile identity';
        ok !exists $profile->{email}, 'builtin public profile excludes private email';
    }
    my $session_response = $request->(GET 'http://localhost/api/session/'.$denied->id.'?_include_relationships=1', Cookie => 'session_id='.$denied->id);
    is $session_response->code, 200, 'builtin SSO session read succeeds';
    my $user_link = decode_json($session_response->content)->{result}{_relationships}{user};
    is $user_link, '/api/user/'.$user->id, 'SSO session advertises builtin user link';
    for my $path ($user_link, '/api/user/'.$user->id) {
        my $response = $request->(GET 'http://localhost'.$path.'?session_id='.$denied->id);
        is $response->code, 200, 'documented SSO query-token user read succeeds';
        is decode_json($response->content)->{result}{id}, $user->id, 'SSO user identity';
        unlike $response->content, qr/"email"\s*:/, 'SSO public read excludes private email';
    }
    my $guarded = $request->(GET 'http://localhost/api/guardeduser/'.$user->id.'/apikeys', Cookie => 'session_id='.$denied->id);
    is $guarded->code, 401, 'verify_user still refuses failed permission context';
    is decode_json($guarded->content)->{error}{message}, 'User required for access.', 'existing relationship user guard error';
    my $missing = $request->(GET 'http://localhost/api/user/00000000-0000-0000-0000-000000000000');
    is $missing->code, 404, 'public read retains missing-object error';
    my $anonymous = $request->(GET 'http://localhost/anonymous-description', Cookie => 'session_id='.$denied->id);
    is $anonymous->code, 200, 'explicit anonymous description succeeds';
    ok !exists decode_json($anonymous->content)->{result}{email}, 'explicit anonymous context cannot reacquire owner email';
    my $list = $request->(GET 'http://localhost/anonymous-list', Cookie => 'session_id='.$denied->id);
    is $list->code, 200, 'explicit anonymous list succeeds' or diag $list->content;
    ok !exists decode_json($list->content)->{result}{items}[0]{email}, 'explicit anonymous list cannot reacquire owner email';
    my $related = $request->(GET 'http://localhost/api/protecteduser/'.$user->id.'/apikeys', Cookie => 'session_id='.$denied->id);
    is $related->code, 200, 'generated list retains public read' or diag $related->content;
    ok !exists decode_json($related->content)->{result}{items}[0]{private_key}, 'denied list excludes private key';
    for my $path ('/api/protecteduser/'.$user->id.'/apikeys',
                  '/api/protectedkey/'.$key->id.'/user') {
        for my $session (undef, '00000000-0000-0000-0000-000000000000', $expired->id, $denied->id) {
            my $response = $request->(GET 'http://localhost'.$path.'?_include_related_objects=1&_include_relationships=1',
                (defined $session ? (Cookie => 'session_id='.$session) : ()));
            is $response->code, 200, 'generated relationship retains public read';
            my $body = decode_json($response->content);
            my $result = $body->{result};
            $result = $result->{items}[0] if exists $result->{items};
            ok defined $result->{id}, 'public relationship identity remains available';
            unlike $response->content, qr/"(?:email|private_key)"\s*:/, 'every public relationship and expansion excludes private fields';
        }
    }
    for my $session (undef, '00000000-0000-0000-0000-000000000000', $expired->id, $denied->id) {
        my $response = $request->(GET 'http://localhost/api/protecteduser/'.$user->id.'?_include_related_objects=1&_include_relationships=1',
            (defined $session ? (Cookie => 'session_id='.$session) : ()));
        is $response->code, 200, 'permissioned singleton retains public reads';
        my $profile = decode_json($response->content)->{result};
        is $profile->{id}, $user->id, 'public singleton identity';
        ok !exists $profile->{email} && !exists $profile->{_relationships}{apikeys}, 'public singleton excludes private fields and links';
    }
    for my $type (qw(emptyuser undefineduser)) {
        is $request->(GET 'http://localhost/api/'.$type.'/'.$user->id)->code, 200, 'empty permissions retain anonymous public read';
        my $response = $request->(GET 'http://localhost/api/'.$type.'/'.$user->id, Cookie => 'session_id='.$denied->id);
        is decode_json($response->content)->{result}{email}, 'read-owner@example.invalid', 'empty permissions retain owner visibility';
    }
    for my $path ('/api/publicuser/'.$user->id, '/anonymous-description', '/anonymous-list', '/implicit-description', '/implicit-list') {
        my $response = $request->(GET 'http://localhost'.$path.'?_include_relationships=1&_include_related_objects=1');
        is $response->code, 200, 'anonymous no-permission read succeeds';
        my $result = decode_json($response->content)->{result};
        $result = $result->{items}[0] if exists $result->{items};
        is $result->{id}, $user->id, 'public identity remains visible';
        ok !exists $result->{email}, 'anonymous response excludes private email';
        ok !exists $result->{_relationships}{apikeys}, 'anonymous response excludes private relationship';
    }
    for my $path ('/api/user/'.$user->id, '/api/protecteduser/'.$user->id, '/api/publicuser/'.$user->id, '/implicit-description', '/implicit-list', '/api/protectedkey/'.$key->id.'/user') {
        my $response = $request->(GET 'http://localhost'.$path, Cookie => 'session_id='.$allowed->id);
        is $response->code, 200, 'authorized owner read succeeds';
        my $result = decode_json($response->content)->{result};
        $result = $result->{items}[0] if exists $result->{items};
        is $result->{email}, 'read-owner@example.invalid', 'authorized private fields preserved';
    }
    my $owner_list = $request->(GET 'http://localhost/api/protecteduser/'.$user->id.'/apikeys?_include_related_objects=user', Cookie => 'session_id='.$allowed->id);
    is $owner_list->code, 200, 'authorized relationship list with expansion succeeds';
    my $owner_item = decode_json($owner_list->content)->{result}{items}[0];
    ok exists $owner_item->{private_key}, 'owner list retains private fields';
    ok !exists $owner_item->{user}{email}, 'expanded parent retains public-only description contract';
    for my $path ('/api/publickey/'.$key->id.'/user', '/api/publicuser/'.$user->id.'/apikeys?_include_related_objects=user') {
        my $response = $request->(GET 'http://localhost'.$path);
        is $response->code, 200, 'anonymous generated relationship succeeds';
        my $result = decode_json($response->content)->{result};
        $result = $result->{items}[0] if exists $result->{items};
        ok defined $result->{id}, 'anonymous relationship has public identity';
        unlike $response->content, qr/"(?:email|private_key)"\s*:/, 'anonymous relationship and expansions exclude private fields';
    }
    unlike $res->content, qr/read-owner\@example\.invalid/, 'private email is absent';
};
is_deeply(Wing->config->get('tenants'), $original_tenants, 'test preserves original tenant configuration');
done_testing;

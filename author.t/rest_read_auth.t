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
my $user = Wing->db->resultset('User')->new({username => 'read-owner', email => 'read-owner@example.invalid'});
$user->encrypt_and_set_password('read-password');
$user->insert;
my $key = $user->apikeys->create({name => 'read-key'});
my $denied = $user->start_session({sso => 1, api_key_id => $key->id});
generate_relationship('ProtectedUser', 'apikeys', db_class_name => 'User', permissions => ['view_my_account']);
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
my $app = Dancer::Handler->get_handler->psgi_app;
test_psgi $app, sub {
    my $request = shift;
    my $res = $request->(GET 'http://localhost/api/protecteduser/'.$user->id, Cookie => 'session_id='.$denied->id);
    is $res->code, 450, 'owning SSO user without permission receives original refusal';
    my $data = decode_json($res->content);
    ok !exists $data->{result}, 'denied permission cannot expose an owner description';
    my $anonymous = $request->(GET 'http://localhost/anonymous-description', Cookie => 'session_id='.$denied->id);
    is $anonymous->code, 200, 'explicit anonymous description succeeds';
    ok !exists decode_json($anonymous->content)->{result}{email}, 'explicit anonymous context cannot reacquire owner email';
    my $list = $request->(GET 'http://localhost/anonymous-list', Cookie => 'session_id='.$denied->id);
    is $list->code, 200, 'explicit anonymous list succeeds' or diag $list->content;
    ok !exists decode_json($list->content)->{result}{items}[0]{email}, 'explicit anonymous list cannot reacquire owner email';
    my $related = $request->(GET 'http://localhost/api/protecteduser/'.$user->id.'/apikeys', Cookie => 'session_id='.$denied->id);
    is $related->code, 450, 'generated list preserves permission refusal' or diag $related->content;
    ok !exists decode_json($related->content)->{result}, 'denied relationship has no result';
    for my $path ('/api/protecteduser/'.$user->id,
                  '/api/protecteduser/'.$user->id.'/apikeys',
                  '/api/protectedkey/'.$key->id.'/user') {
        for my $case ([undef, 441, 'session_id is required'],
                      ['00000000-0000-0000-0000-000000000000', 401, 'You must log in to do that.'],
                      [$expired->id, 401, 'You must log in to do that.'],
                      [$denied->id, 450, 'Insufficient permissions.']) {
            my $response = $request->(GET 'http://localhost'.$path.'?_include_related_objects=1&_include_relationships=1',
                (defined $case->[0] ? (Cookie => 'session_id='.$case->[0]) : ()));
            is $response->code, $case->[1], 'generated read preserves original auth status';
            my $body = decode_json($response->content);
            is $body->{error}{message}, $case->[2], 'original authentication message';
            ok !exists $body->{result}, 'refusal has no expanded or private result';
        }
    }
    for my $type (qw(emptyuser undefineduser)) {
        is $request->(GET 'http://localhost/api/'.$type.'/'.$user->id)->code, 441, 'present permissions require auth';
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
    for my $path ('/api/protecteduser/'.$user->id, '/api/publicuser/'.$user->id, '/implicit-description', '/implicit-list', '/api/protectedkey/'.$key->id.'/user') {
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
        ok !exists $result->{email} && !exists $result->{private_key}, 'anonymous relationship excludes private fields';
    }
    unlike $res->content, qr/read-owner\@example\.invalid/, 'private email is absent';
};
done_testing;

use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Wing;
use Wing::Rest;
use Plack::Test;
use Dancer::Handler;
use HTTP::Request::Common qw(GET POST PUT DELETE);
use JSON qw(decode_json);

set show_errors => 0;
my $user = Wing->db->resultset('User')->create({username => 'crud-owner', email => 'crud-owner@example.invalid'});
my $key = $user->apikeys->create({name => 'denied-crud-key'});
my $denied = $user->start_session({sso => 1, api_key_id => $key->id});
generate_crud('User', permissions => ['edit_my_account']);
my $processed = 0;
generate_crud('Account', db_class_name => 'User', permissions => ['edit_my_account'],
    extra_processing => sub { $processed++; $_[0]->real_name('Processed through CRUD') });
generate_crud('NullableCallback', db_class_name => 'User', permissions => [], extra_processing => undef);
my $allowed_key = $user->apikeys->create({name => 'allowed-crud-key'});
Wing->db->resultset('APIKeyPermission')->create({user_id => $user->id, api_key_id => $allowed_key->id, permission => 'edit_my_account'});
my $allowed = $user->start_session({sso => 1, api_key_id => $allowed_key->id});
my $admin = Wing->db->resultset('User')->create({username => 'crud-admin', admin => 1});
my $admin_session = $admin->start_session({sso => 0});
my $view_key = $user->apikeys->create({name => 'view-crud-key'});
Wing->db->resultset('APIKeyPermission')->create({user_id => $user->id, api_key_id => $view_key->id, permission => 'view_my_account'});
my $view_session = $user->start_session({sso => 1, api_key_id => $view_key->id});
require Wing::Rest::APIKey;
my $limited_user = Wing->db->resultset('User')->create({username => 'crud-limited', email => 'crud-limited@example.invalid'});
my $limited_session = $limited_user->start_session({sso => 0});
Wing->cache->set('rpc_count_'.$_.$limited_user->id, 1000) for 0..59;
my $app = Dancer::Handler->get_handler->psgi_app;
test_psgi $app, sub {
    my $request = shift;
    my $options_method = TestWing::DB::Result::User->can('field_options');
    my @contexts;
    no warnings 'redefine';
    local *TestWing::DB::Result::User::field_options = sub {
        my ($object, %options) = @_;
        push @contexts, $options{current_user};
        return $options_method->(@_);
    };
    my $denied_metadata = $request->(GET 'http://localhost/api/account/_options', Cookie => 'session_id='.$denied->id);
    is $denied_metadata->code, 200, 'denied metadata retains public response';
    ok @contexts && !defined $contexts[-1], 'metadata cannot reacquire denied user context';
    my $limited_metadata = $request->(GET 'http://localhost/api/account/_options', Cookie => 'session_id='.$limited_session->id);
    is $limited_metadata->code, 452, 'metadata propagates rate limits';
    my $metadata = $request->(GET 'http://localhost/api/account/_options');
    is $metadata->code, 200, 'aliased CRUD metadata uses the supplied database class' or diag $metadata->content;
    my $response = $request->(PUT 'http://localhost/api/user/'.$user->id,
        Cookie => 'session_id='.$denied->id, Content => [real_name => 'Must be refused']);
    is $response->code, 450, 'CRUD refuses an owning SSO client without the requested permission';
    is decode_json($response->content)->{error}{message}, 'Insufficient permissions.', 'original permission refusal';
    my $cookie = 'session_id='.$admin_session->id;
    my $created = $request->(POST 'http://localhost/api/account', Cookie => $cookie,
        Content => [username => 'crud-created', email => 'crud-created@example.invalid', password => 'created-password']);
    is $created->code, 200, 'aliased CRUD creates with an authorized admin' or diag $created->content;
    my $id = decode_json($created->content)->{result}{id};
    ok $id, 'create returns identity';
    my $read = $request->(GET 'http://localhost/api/account/'.$id, Cookie => $cookie);
    is decode_json($read->content)->{result}{real_name}, 'Processed through CRUD', 'HTTP read observes create callback';
    my $updated = $request->(PUT 'http://localhost/api/account/'.$id, Cookie => $cookie,
        Content => [real_name => 'Caller value']);
    is $updated->code, 200, 'aliased CRUD updates with an authorized admin';
    $read = $request->(GET 'http://localhost/api/account/'.$id, Cookie => $cookie);
    is decode_json($read->content)->{result}{real_name}, 'Processed through CRUD', 'HTTP read observes update callback';
    my $deleted = $request->(DELETE 'http://localhost/api/account/'.$id, Cookie => $cookie);
    is $deleted->code, 200, 'aliased CRUD deletes with an authorized admin';
    is $request->(GET 'http://localhost/api/account/'.$id)->code, 404, 'HTTP observes deletion';
    is $processed, 3, 'each mutation invokes the supplied callback';
    my $plain = $request->(POST 'http://localhost/api/nullablecallback', Cookie => $cookie,
        Content => [username => 'crud-null-callback', email => 'crud-null@example.invalid', password => 'created-password']);
    is $plain->code, 200, 'undefined callback permits create';
    my $plain_id = decode_json($plain->content)->{result}{id};
    is $request->(PUT 'http://localhost/api/nullablecallback/'.$plain_id, Cookie => $cookie,
        Content => [real_name => 'No callback'])->code, 200, 'undefined callback permits update';
    is $request->(DELETE 'http://localhost/api/nullablecallback/'.$plain_id, Cookie => $cookie)->code,
        200, 'undefined callback permits delete';
    is $request->(GET 'http://localhost/api/nullablecallback/'.$plain_id)->code, 404, 'undefined callback deletion persists';
    my $view = $request->(GET 'http://localhost/api/apikey/'.$key->id, Cookie => 'session_id='.$view_session->id);
    is $view->code, 200, 'built-in APIKey read accepts view-only owner';
    ok exists decode_json($view->content)->{result}{private_key}, 'view-only owner retains private APIKey fields';
    my $builtin = $request->(PUT 'http://localhost/api/apikey/'.$key->id,
        Cookie => 'session_id='.$denied->id, Content => [name => 'Refused']);
    is $builtin->code, 450, 'built-in APIKey CRUD enforces its declared permission';
    $builtin = $request->(PUT 'http://localhost/api/apikey/'.$key->id,
        Cookie => 'session_id='.$allowed->id, Content => [name => 'Allowed']);
    is $builtin->code, 200, 'built-in APIKey CRUD accepts authorized owner';
};
done_testing;

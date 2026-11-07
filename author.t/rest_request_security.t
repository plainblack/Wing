use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Wing;
use Wing::Rest;
use Wing::Rest::Session;

use Plack::Test;
use Dancer::Handler;
use HTTP::Request::Common qw(GET POST PUT DELETE);
use JSON qw(encode_json decode_json);

set show_errors => 0;
set behind_proxy => 0;
my $user = Wing->db->resultset('User')->new({username => 'origin-developer', developer => 1, admin => 1});
$user->encrypt_and_set_password('origin-password');
$user->insert;
my $key = $user->apikeys->create({name => 'origin-key'});
my $session = $user->start_session({api_key_id => $key->id, ip_address => '127.0.0.1'});
my $cookie = 'session_id='.$session->id;
generate_crud('User');
for my $method (qw(post put patch del)) {
    Dancer->can($method)->('/api/custom' => sub { return {user_id => get_user_by_session_id()->id} });
}
my $app = Dancer::Handler->get_handler->psgi_app;
test_psgi $app, sub {
    my $request = shift;
    for my $headers ([Origin => 'https://app.example'], [Origin => 'null'], ['Sec-Fetch-Site' => 'cross-site']) {
        for my $method (qw(POST PUT PATCH DELETE)) {
            my $res = $request->(HTTP::Request->new($method, 'http://localhost/api/custom',
                [@$headers, 'Content-Type' => 'application/x-www-form-urlencoded'], 'session_id='.$session->id));
            is $res->code, 200, "$method with @$headers and explicit session_id works" or diag $res->content;
            is decode_json($res->content)->{result}{user_id}, $user->id, 'explicit session authenticates user';
        }
        my $json = $request->(POST 'http://localhost/api/custom', @$headers,
            'Content-Type' => 'application/json', Content => encode_json({session_id => $session->id}));
        is $json->code, 200, "JSON explicit session_id with @$headers works";
        my $ambient = $request->(POST 'http://localhost/api/custom', @$headers, Cookie => $cookie);
        is $ambient->code, 200, "cookie session with @$headers works";
        my $anonymous = $request->(POST 'http://localhost/api/custom', @$headers);
        is $anonymous->code, 441, "no credentials with @$headers reach normal authentication";
        my $login = $request->(POST 'http://localhost/api/session', @$headers,
            Content => [username => $user->username, password => 'origin-password', api_key_id => $key->id]);
        is $login->code, 200, "developer login with @$headers succeeds";
        like $login->header('Set-Cookie'), qr/session_id=.*SameSite=Lax/, 'login writes the Lax session cookie';
        my $login_id = decode_json($login->content)->{result}{id};
        my $logout = $request->(DELETE 'http://localhost/api/session/'.$login_id, @$headers);
        is $logout->code, 200, "logout with @$headers uses the explicit path credential";
        my $ended = $request->(POST 'http://localhost/api/custom', @$headers, Content => [session_id => $login_id]);
        is $ended->code, 401, 'logged-out session no longer authenticates';
    }
    my @cross = (Origin => 'https://app.example');
    my $created = $request->(POST 'http://localhost/api/user', @cross,
        Content => [session_id => $session->id, username => 'origin-created', email => 'origin-created@example.invalid', password => 'created-password']);
    is $created->code, 200, 'cross-origin generated create succeeds' or diag $created->content;
    my $id = decode_json($created->content)->{result}{id};
    my $updated = $request->(PUT 'http://localhost/api/user/'.$id, @cross,
        'Content-Type' => 'application/json', Content => encode_json({session_id => $session->id, real_name => 'Updated via REST'}));
    is $updated->code, 200, 'cross-origin generated update succeeds';
    my $read = $request->(GET 'http://localhost/api/user/'.$id, Cookie => $cookie);
    is decode_json($read->content)->{result}{real_name}, 'Updated via REST', 'HTTP read observes persisted update';
    my $deleted = $request->(DELETE 'http://localhost/api/user/'.$id.'?session_id='.$session->id, @cross);
    is $deleted->code, 200, 'cross-origin generated delete succeeds';
    my $missing = $request->(GET 'http://localhost/api/user/'.$id, Cookie => $cookie);
    is $missing->code, 404, 'HTTP read observes deletion';
};
ok !Wing::RequestSecurity->can('same_origin_error'), 'Wing has no origin check';
done_testing;

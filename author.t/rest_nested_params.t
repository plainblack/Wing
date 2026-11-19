use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Wing;
use Wing::Rest;
use Wing::Rest::Session;
use Wing::Rest::Idea;

use Plack::Test;
use Dancer::Handler;
use HTTP::Request::Common qw(GET POST PUT);
use JSON qw(encode_json decode_json);
use Data::GUID;

{
    # A route an app defines in its own module, away from Wing::Rest.
    package TestApp::Probe;
    use Dancer ':syntax';
    use Wing::Rest;
    post '/api/probe' => sub { return {ids => params->{ids}, flag => params->{flag} ? 1 : 0} };
    post '/api/probe-list' => sub { return format_list(site_db()->resultset('User'), current_user => undef) };
    get '/api/probe-splat/**' => sub { my ($parts) = splat; return {parts => $parts} };
    any ['post', 'put'] => '/api/probe-webhook/:id' => sub { return {data => ref params->{data}} };
    allow_nested_params(post => '/api/probe-webhook/:id');
}

set show_errors => 0;
my $user = Wing->db->resultset('User')->new({username => 'nested-developer', email => 'nested-developer@example.invalid', developer => 1, admin => 1});
$user->encrypt_and_set_password('nested-password');
$user->insert;
my $key = $user->apikeys->create({name => 'nested-key'});
my $session = $user->start_session({api_key_id => $key->id, ip_address => '127.0.0.1'});
generate_crud('User');

my $injection = {'= 0 OR 1=' => 'x'};
my $app = Dancer::Handler->get_handler->psgi_app;
my $json = sub {
    my ($method, $url, $body) = @_;
    return HTTP::Request->new($method, 'http://localhost'.$url, ['Content-Type' => 'application/json'], encode_json($body));
};
my $refused = sub {
    my ($res, $name, $label) = @_;
    is $res->code, 442, $label or diag $res->content;
    is decode_json($res->content)->{error}{data}, $name, "$label names the $name param";
};

test_psgi $app, sub {
    my $request = shift;

    my $ok = $request->($json->(POST => '/api/probe', {ids => [1, 2, 3], flag => JSON::true}));
    is $ok->code, 200, 'a list of plain values and a JSON boolean are accepted' or diag $ok->content;
    is_deeply decode_json($ok->content)->{result}, {ids => [1, 2, 3], flag => 1}, 'the route sees them unchanged';

    $refused->($request->($json->(POST => '/api/probe', {ids => $injection})),
        'ids', 'an object param is refused on an app route');
    $refused->($request->($json->(POST => '/api/probe', {ids => [1, $injection]})),
        'ids', 'a list holding an object is refused on an app route');
    $refused->($request->($json->(POST => '/api/probe', {ids => [1, [2]]})),
        'ids', 'a list holding a list is refused on an app route');
    $refused->($request->($json->(POST => '/api/session', {username => $injection, password => 'x', api_key_id => $key->id})),
        'username', 'an object username is refused on a Wing route');

    my $splat = $request->(GET '/api/probe-splat/a/b');
    is $splat->code, 200, 'a megasplat route still works' or diag $splat->content;
    is_deeply decode_json($splat->content)->{result}{parts}, ['a', 'b'], 'the route sees its megasplat';

    my $hook = $request->($json->(POST => '/api/probe-webhook/7', {data => $injection}));
    is $hook->code, 200, 'a route opted out with allow_nested_params takes an object' or diag $hook->content;
    is decode_json($hook->content)->{result}{data}, 'HASH', 'the opted-out route sees the object';
    $refused->($request->($json->(PUT => '/api/probe-webhook/7', {data => $injection})),
        'data', 'the opt-out covers only the method it names');

    my $tenant = Data::GUID->guid_string;
    Wing->config->set('tenants/sso_key', $tenant);
    $refused->($request->(POST '/api/session/tenantsso', [api_key => $tenant, password => 'x', username => 'a', username => 'b']),
        'username', 'tenant SSO refuses a list of usernames');
    $refused->($request->(POST '/api/session/tenantsso', [api_key => $tenant, password => 'x', user_id => 'a', user_id => 'b']),
        'user_id', 'tenant SSO refuses a list of user ids');
    Wing->config->delete('tenants/sso_key');

    {
        # Wing's own call sites must stay safe even when the hook is not there.
        local Dancer::Factory::Hook->instance->hooks->{before} = [];
        $refused->($request->($json->(POST => '/api/session', {username => $injection, password => 'x', api_key_id => $key->id})),
            'username', 'session login refuses an object username without the hook');
        $refused->($request->($json->(POST => '/api/session', {username => $user->username, password => 'x', api_key_id => $injection})),
            'api_key_id', 'session login refuses an object api_key_id without the hook');
        $refused->($request->($json->(PUT => '/api/user/'.$user->id, {session_id => $session->id, id => $injection})),
            'id', 'fetch_object refuses an object id without the hook');
        $refused->($request->($json->(POST => '/api/probe-list', {_order_by => [$injection]})),
            '_order_by', 'format_list refuses an object in _order_by without the hook');
        $refused->($request->($json->(POST => '/api/probe-list', {_page_number => $injection})),
            '_page_number', 'format_list refuses an object _page_number without the hook');
        $refused->($request->(GET '/api/idea?_sort_status=Open&_sort_status=Closed'),
            '_sort_status', 'idea search refuses a list where it takes one value');
        my $list = $request->($json->(POST => '/api/probe-list', {_order_by => ['username', 'id'], _include_related_objects => ['apikeys']}));
        is $list->code, 200, 'format_list still takes lists of plain names' or diag $list->content;
    }
};

done_testing;

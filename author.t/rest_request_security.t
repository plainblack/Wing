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
my $custom_runs = 0;
for my $method (qw(get options post put patch del)) {
    Dancer->can($method)->('/api/custom' => sub {
        $custom_runs++;
        return {user_id => get_user_by_session_id()->id};
    });
}
my $queries = 0;
Wing->db->storage->debugcb(sub { $queries++ });
Wing->db->storage->debug(1);
my $app = Dancer::Handler->get_handler->psgi_app;
test_psgi $app, sub {
    my $request = shift;
    my $cache_calls = 0;
    my $get = CHI::Driver->can('get');
    my $set = CHI::Driver->can('set');
    my $remove = CHI::Driver->can('remove');
    no warnings qw(redefine once);
    local *CHI::Driver::get = sub { $cache_calls++; return $get->(@_) };
    local *CHI::Driver::set = sub { $cache_calls++; return $set->(@_) };
    local *CHI::Driver::remove = sub { $cache_calls++; return $remove->(@_) };
    for my $route (
        ['POST', '/api/session'], ['POST', '/api/user'],
        ['PUT', '/api/user/'.$user->id], ['DELETE', '/api/user/'.$user->id],
        ['POST', '/api/custom'], ['PATCH', '/api/custom'],
    ) {
        for my $headers (
            [Origin => 'http://evil.example'], [Origin => 'null'], [Origin => ''],
            [Origin => 'https://localhost'], [Origin => 'http://localhost:81'],
            [Origin => 'http://localhost.evil.example'], [Origin => 'http://evil.example@localhost'],
            [Origin => 'http://localhost/path'], [Origin => 'http://localhost:bad'],
            [Origin => 'http://localhost', Origin => 'http://evil.example'],
            ['Sec-Fetch-Site' => 'cross-site'],
            [Origin => 'http://localhost', 'Sec-Fetch-Site' => 'cross-site'],
        ) {
            for my $body (
                ['application/x-www-form-urlencoded', 'session_id=&username=origin-developer&password=origin-password&api_key_id='.$key->id],
                ['application/json', encode_json({session_id => JSON::false, username => $user->username, password => 'origin-password', api_key_id => $key->id})],
            ) {
                my ($sql_before, $cache_before, $runs_before) = ($queries, $cache_calls, $custom_runs);
                my $res = $request->(HTTP::Request->new($route->[0], 'http://localhost'.$route->[1],
                    [@$headers, Cookie => $cookie, 'Content-Type' => $body->[0]], $body->[1]));
                is $res->code, 403, "$route->[0] $route->[1] refuses @$headers ($body->[0])";
                my $data = eval { decode_json($res->content) };
                is ref($data), 'HASH', 'refusal is JSON';
                is $data->{error}{code}, 403, 'Wing error code is 403';
                like $data->{error}{message}, qr/same origin.*Reload/i, 'actionable Wing error';
                ok !exists $data->{result}, 'error is not wrapped as a successful result';
                is $queries, $sql_before, 'zero SQL lookup or mutation';
                is $cache_calls, $cache_before, 'zero cache lookup or mutation';
                is $custom_runs, $runs_before, 'custom route never runs';
                ok !$res->header('Set-Cookie'), 'no cookie written';
            }
        }
    }
    for my $value (undef, '', 0, 'malformed', [], {}, JSON::false, $session->id) {
        for my $cookie_header ([], [Cookie => $cookie]) {
            my ($sql_before, $cache_before) = ($queries, $cache_calls);
            my $res = $request->(POST 'http://localhost/api/session', @$cookie_header,
                Origin => 'http://evil.example', 'Content-Type' => 'application/json',
                Content => encode_json({session_id => $value, username => $user->username,
                    password => 'origin-password', api_key_id => $key->id}));
            is $res->code, 403, 'no parameter exemption, with or without ambient cookie';
            ok !$res->header('Set-Cookie'), 'refused credential login never writes cookie';
            is $queries, $sql_before, 'credential refusal precedes SQL';
            is $cache_calls, $cache_before, 'credential refusal precedes cache';
        }
    }
    my $previous_rest = encode_json(Wing->config->get('rest'));
    my $opt_in_ok = eval {
        Wing->config->set('rest/allow_cookieless_cross_origin_writes', 1);
        my $cross = $request->(POST 'http://localhost/api/custom', Origin => 'http://evil.example',
            Content => [session_id => $session->id]);
        is $cross->code, 200, 'opt-in allows cross-origin explicit-session authentication without cookies';
        is decode_json($cross->content)->{result}{user_id}, $user->id, 'normal authentication identifies developer';
        my $login = $request->(POST 'http://localhost/api/session', Origin => 'http://evil.example',
            Content => [username => $user->username, password => 'origin-password', api_key_id => $key->id]);
        is $login->code, 200, 'opt-in permits cookieless cross-origin developer login';
        ok !$login->header('Set-Cookie'), 'cross-origin form login cannot install an attacker session cookie';
        my $login_id = decode_json($login->content)->{result}{id};
        ok $login_id, 'cross-origin login returns explicit session token';
        my $authenticated = $request->(POST 'http://localhost/api/custom', Origin => 'http://evil.example',
            Content => [session_id => $login_id]);
        is $authenticated->code, 200, 'returned session token works through normal authentication';
        for my $headers ([Origin => 'http://evil.example'], [Origin => 'null'],
            [Origin => '::::'], ['Sec-Fetch-Site' => 'cross-site']) {
            my $anonymous = $request->(POST 'http://localhost/api/custom', @$headers);
            is $anonymous->code, 441, 'cookieless request without token reaches normal authentication';
            for my $ambient ('session_id='.$session->id, 'cart_id=guest-cart',
                'session_id=; cart_id=guest-cart', 'application_credential=present', '') {
                for my $route (['POST', '/api/session'], ['POST', '/api/custom'],
                    ['PUT', '/api/user/'.$user->id], ['DELETE', '/api/session/'.$session->id]) {
                    my ($sql_before, $cache_before, $runs_before) = ($queries, $cache_calls, $custom_runs);
                    my $res = $request->(HTTP::Request->new($route->[0], 'http://localhost'.$route->[1],
                        [@$headers, Cookie => $ambient, 'Content-Type' => 'application/x-www-form-urlencoded'],
                        'session_id='.$session->id.'&username=origin-developer&password=origin-password&api_key_id='.$key->id));
                    is $res->code, 403, 'opt-in still refuses every Cookie header even with an explicit token';
                    is $queries, $sql_before, 'cookie refusal precedes SQL';
                    is $cache_calls, $cache_before, 'cookie refusal precedes cache';
                    is $custom_runs, $runs_before, 'cookie refusal precedes route execution';
                    ok !$res->header('Set-Cookie'), 'cookie refusal issues no cookie';
                }
            }
            my $res = $request->(POST 'http://localhost/api/session', @$headers,
                Content => [username => $user->username, password => 'origin-password', api_key_id => $key->id]);
            is $res->code, 200, 'opt-in cookieless login accepts origin refusal variants';
            ok !$res->header('Set-Cookie'), 'origin refusal variants cannot install login cookie';
        }
        my $logout = $request->(DELETE 'http://localhost/api/session/'.$login_id, Origin => 'http://evil.example');
        is $logout->code, 200, 'cookieless cross-origin logout uses explicit path credential';
        my $ended = $request->(POST 'http://localhost/api/custom', Origin => 'http://evil.example',
            Content => [session_id => $login_id]);
        is $ended->code, 401, 'logged-out token no longer authenticates';
        1;
    };
    my $opt_in_error = $@;
    my $rest = decode_json($previous_rest);
    defined $rest ? Wing->config->set('rest', $rest) : Wing->config->delete('rest');
    die $opt_in_error unless $opt_in_ok;
    for my $method (qw(GET HEAD OPTIONS)) {
        my $res = $request->(HTTP::Request->new($method, 'http://localhost/api/custom',
            [Cookie => $cookie, Origin => 'null', 'Sec-Fetch-Site' => 'cross-site']));
        is $res->code, 200, "$method retains existing behavior";
    }
    for my $headers ([], [Origin => 'http://LOCALHOST:80'], ['Sec-Fetch-Site' => 'same-origin']) {
        my $res = $request->(POST 'http://localhost/api/session', @$headers,
            Content => [username => $user->username, password => 'origin-password', api_key_id => $key->id]);
        is $res->code, 200, 'headerless and same-origin credential login succeed';
        like $res->header('Set-Cookie'), qr/session_id=/, 'supported login writes cookie';
        for my $format ('form', 'json') {
            my @content = $format eq 'form' ? (Content => [session_id => $session->id])
                : ('Content-Type' => 'application/json', Content => encode_json({session_id => $session->id}));
            my $custom = $request->(POST 'http://localhost/api/custom', @$headers, @content);
            is $custom->code, 200, "explicit $format session parameter works";
            is decode_json($custom->content)->{result}{user_id}, $user->id, 'explicit session authenticates user';
        }
        my $custom = $request->(POST 'http://localhost/api/custom', @$headers, Cookie => $cookie);
        is $custom->code, 200, 'ambient cookie remains supported';
    }
    for my $case (
        ['https://localhost/api/custom', 0, [], 'https://LOCALHOST:443'],
        ['http://internal/api/custom', 1, ['X-Forwarded-Proto' => 'https', 'X-Forwarded-Host' => 'public.example:8443'], 'https://public.example:8443'],
    ) {
        set behind_proxy => $case->[1];
        my $res = $request->(POST $case->[0], @{$case->[2]}, Cookie => $cookie, Origin => $case->[3]);
        is $res->code, 200, 'native and trusted forwarded origins work';
    }
    set behind_proxy => 0;
    my $spoofed = $request->(POST 'http://localhost/api/custom', Cookie => $cookie,
        'X-Forwarded-Host' => 'evil.example', Origin => 'http://evil.example');
    is $spoofed->code, 403, 'untrusted forwarding cannot override target origin';
    my $created = $request->(POST 'http://localhost/api/user', Cookie => $cookie,
        Origin => 'http://localhost', Content => [username => 'origin-created', email => 'origin-created@example.invalid', password => 'created-password']);
    is $created->code, 200, 'generated create succeeds' or diag $created->content;
    my $id = decode_json($created->content)->{result}{id};
    ok $id, 'created object has an id';
    my $updated = $request->(PUT 'http://localhost/api/user/'.$id, Cookie => $cookie,
        'Content-Type' => 'application/json', Content => encode_json({real_name => 'Updated via REST'}));
    is $updated->code, 200, 'generated update succeeds for headerless client';
    my $read = $request->(GET 'http://localhost/api/user/'.$id, Cookie => $cookie);
    is decode_json($read->content)->{result}{real_name}, 'Updated via REST', 'HTTP read observes persisted update';
    my $deleted = $request->(DELETE 'http://localhost/api/user/'.$id, Cookie => $cookie, Origin => 'http://localhost');
    is $deleted->code, 200, 'generated delete succeeds';
    my $missing = $request->(GET 'http://localhost/api/user/'.$id, Cookie => $cookie);
    is $missing->code, 404, 'HTTP read observes deletion';
};
done_testing;

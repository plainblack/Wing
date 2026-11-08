use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Wing;
use Wing::Rest;
use Plack::Test;
use Dancer::Handler;
use HTTP::Request::Common qw(GET POST PUT DELETE);
use JSON qw(encode_json decode_json);

set show_errors => 0;
set behind_proxy => 0;
sub make_user {
    my ($name) = @_;
    my $user = Wing->db->resultset('User')->new({username => $name, email => $name.'@example.invalid'});
    $user->encrypt_and_set_password('auth-password');
    return $user->insert;
}
my $user = make_user('auth-owner');
my $key = $user->apikeys->create({name => 'auth-key'});
Wing->db->resultset('APIKeyPermission')->create({user_id => $user->id, api_key_id => $key->id, permission => 'edit_my_account'});
my $denied_key = $user->apikeys->create({name => 'denied-key'});
my $denied = $user->start_session({sso => 1, api_key_id => $denied_key->id});
my $expired = $user->start_session({sso => 1, api_key_id => $key->id});
Wing->cache->expire($expired->key);
my $inactive_user = make_user('auth-inactive');
my $inactive = $inactive_user->start_session({sso => 1, api_key_id => $key->id});
$inactive_user->permanently_deactivated(1);
$inactive_user->update;
my $limited_user = make_user('auth-limited');
my $limited = $limited_user->start_session({sso => 0});
# Populate every minute bucket so the test does not depend on a clock boundary.
Wing->cache->set('rpc_count_'.$_.$limited_user->id, 1000) for 0..59;
my $admin = make_user('auth-admin');
$admin->admin(1);
$admin->update;
my $admin_session = $admin->start_session({sso => 1, api_key_id => $key->id});
my $target = make_user('auth-target');
my %calls;
for my $spec (['ProtectedUser', [permissions => ['edit_my_account']]],
              ['EmptyUser', [permissions => []]], ['UndefinedUser', [permissions => undef]],
              ['AnonymousUser', []]) {
    my ($type, $options) = @$spec;
    my @options = (db_class_name => 'User', @$options, extra_processing => sub { $calls{extra_processing}++ });
    generate_crud($type, @options);
}
my @methods = qw(verify_creation_params verify_posted_params can_edit can_delete insert update delete);
my %original = map { $_ => TestWing::DB::Result::User->can($_) } @methods;
my $find = DBIx::Class::ResultSet->can('find');
my $new = DBIx::Class::ResultSet->can('new');
my $app = Dancer::Handler->get_handler->psgi_app;
test_psgi $app, sub {
    my $request = shift;
    no warnings 'redefine';
    no strict 'refs';
    for my $method (@methods) {
        my $original = $original{$method};
        *{'TestWing::DB::Result::User::'.$method} = sub { $calls{$method}++; return $original->(@_) };
    }
    local *DBIx::Class::ResultSet::new = sub {
        $calls{model_construction}++ if ref($_[0]) && $_[0]->result_source->source_name eq 'User'
            && ref($_[1]) eq 'HASH' && !keys %{$_[1]};
        return $new->(@_);
    };
    local *DBIx::Class::ResultSet::find = sub {
        $calls{target_lookup}++ if $_[0]->result_source->source_name eq 'User'
            && defined $_[1] && !ref($_[1]) && $_[1] eq $target->id;
        return $find->(@_);
    };
    for my $case (
        ['missing', undef, 441, 'session_id is required'],
        ['invalid', '00000000-0000-0000-0000-000000000000', 401, 'You must log in to do that.'],
        ['expired', $expired->id, 401, 'You must log in to do that.'],
        ['permission', $denied->id, 450, 'Insufficient permissions.'],
        ['deactivated', $inactive->id, 450, 'Account permanently deactivated'],
        ['rate limited', $limited->id, 452, 'Slow down! You are only allowed to make (30) requests per minute to the server.'],
    ) {
        for my $method (qw(POST PUT DELETE)) {
            %calls = ();
            my $path = '/api/protecteduser'.($method eq 'POST' ? '' : '/'.$target->id);
            my $res = $request->(HTTP::Request->new($method, 'http://localhost'.$path,
                ['Content-Type' => 'application/json'], encode_json({
                    (defined $case->[1] ? (session_id => $case->[1]) : ()),
                    username => 'blocked-create', email => 'blocked@example.invalid', password => 'blocked-password', real_name => 'Blocked',
                })));
            is $res->code, $case->[2], "$method $case->[0] preserves HTTP code";
            my $data = decode_json($res->content);
            is $data->{error}{code}, $case->[2], 'original Wing code';
            is $data->{error}{message}, $case->[3], 'original Wing message';
            ok !exists $data->{result}, 'refusal is not a successful result';
            is_deeply \%calls, {}, 'no target lookup, verification, extra processing or mutation';
        }
    }
    for my $type (qw(emptyuser undefineduser)) {
        for my $method (qw(POST PUT DELETE)) {
            %calls = ();
            my $path = '/api/'.$type.($method eq 'POST' ? '' : '/'.$target->id);
            my $res = $request->(HTTP::Request->new($method, 'http://localhost'.$path));
            is $res->code, 441, "$method $type still requires authentication";
            is_deeply \%calls, {}, 'empty permission refusal precedes model activity';
        }
    }
    my $ungranted = $request->(POST 'http://localhost/api/protecteduser', Cookie => 'session_id='.$admin_session->id,
        Content => [username => 'ungranted-created', email => 'ungranted@example.invalid', password => 'created-password']);
    is $ungranted->code, 450, 'admin app token without edit_my_account is refused';
    Wing->db->resultset('APIKeyPermission')->create({user_id => $admin->id, api_key_id => $key->id, permission => 'edit_my_account'});
    for my $type (qw(protecteduser emptyuser undefineduser anonymoususer)) {
        my $created = $request->(POST 'http://localhost/api/'.$type, Cookie => 'session_id='.$admin_session->id,
            Content => [username => $type.'-created', email => $type.'@example.invalid', password => 'created-password']);
        is $created->code, 200, "$type authorized create succeeds" or diag $created->content;
        my $id = decode_json($created->content)->{result}{id};
        ok $id, 'create returns persisted identity';
        my $created_user = Wing->db->resultset('User')->find($id);
        my $created_session = $created_user->start_session({sso => 1, api_key_id => $key->id});
        Wing->db->resultset('APIKeyPermission')->create({user_id => $id, api_key_id => $key->id, permission => 'edit_my_account'});
        my $cookie = 'session_id='.$created_session->id;
        my $updated = $request->(PUT 'http://localhost/api/'.$type.'/'.$id, Cookie => $cookie,
            Content => [real_name => 'Updated through HTTP']);
        is $updated->code, 200, "$type authorized owner update succeeds" or diag $updated->content;
        my $read = $request->(GET 'http://localhost/api/'.$type.'/'.$id, Cookie => $cookie);
        is decode_json($read->content)->{result}{real_name}, 'Updated through HTTP', 'HTTP observes persisted update';
        my $deleted = $request->(DELETE 'http://localhost/api/'.$type.'/'.$id, Cookie => $cookie);
        is $deleted->code, 200, "$type authorized owner delete succeeds" or diag $deleted->content;
        is $request->(GET 'http://localhost/api/'.$type.'/'.$id)->code, 404, 'HTTP observes deletion';
    }
    for my $credential ([], [Cookie => 'session_id=00000000-0000-0000-0000-000000000000']) {
        %calls = ();
        my $res = $request->(POST 'http://localhost/api/anonymoususer', @$credential,
            Content => [username => 'anonymous', email => 'anonymous@example.invalid', password => 'signup-password']);
        is $res->code, 450, 'no-permissions anonymous create reaches existing model policy';
        is decode_json($res->content)->{error}{message}, 'Insufficient privileges for User.', 'model denial retained';
        ok $calls{verify_creation_params}, 'optional lookup permits anonymous creation verification';
        ok $calls{verify_posted_params}, 'optional lookup permits anonymous field verification';
        ok !$calls{insert}, 'model policy still prevents unauthorized insertion';
        for my $method (qw(PUT DELETE)) {
            %calls = ();
            my $denial = $request->(HTTP::Request->new($method, 'http://localhost/api/anonymoususer/'.$target->id,
                [@$credential, 'Content-Type' => 'application/json'], encode_json({real_name => 'Unauthorized'})));
            is $denial->code, 450, 'optional authentication still respects model policy';
            ok $calls{can_edit}, 'anonymous mutation reaches real model authorization';
            ok !$calls{update} && !$calls{delete}, 'model policy prevents anonymous mutation';
        }
    }
};
done_testing;

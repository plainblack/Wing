use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Wing;
use Wing::Rest;
use Wing::Session;
use Plack::Test;
use Dancer::Handler;
use HTTP::Request::Common qw(GET PUT);
use JSON qw(decode_json);

set show_errors => 0;
set behind_proxy => 0;
my $key;
sub make_user {
    my ($name) = @_;
    my $user = Wing->db->resultset('User')->new({username => $name, email => $name.'@example.invalid'});
    $user->encrypt_and_set_password('ended-password');
    $user->insert;
    $key //= $user->apikeys->create({name => 'ended-key'});
    Wing->db->resultset('APIKeyPermission')->create({user_id => $user->id, api_key_id => $key->id, permission => 'edit_my_account'});
    return $user;
}
sub make_session {
    my ($user, %options) = @_;
    return $user->start_session({sso => 1, api_key_id => $key->id, auth_source => 'site',
        absolute_expires_at => time + 4 * 60 * 60, %options});
}
generate_crud('EndedUser', db_class_name => 'User', permissions => ['edit_my_account']);
generate_crud('DeniedUser', db_class_name => 'User', permissions => ['ended_unheld_permission']);
my ($helper_input, $helper_permissions);
get '/helper-input-probe' => sub {
    my $user = eval { get_user_by_session_id(session_id => $helper_input, permissions => $helper_permissions) };
    return defined $user ? 'user '.$user->id : 'error '.(ref $@ eq 'Ouch' ? $@->code : $@);
};
my @methods = qw(verify_posted_params can_edit update);
my %original = map { $_ => TestWing::DB::Result::User->can($_) } @methods;
my %calls;
{
    no warnings 'redefine';
    no strict 'refs';
    for my $method (@methods) {
        my $original = $original{$method};
        *{'TestWing::DB::Result::User::'.$method} = sub { $calls{$method}++; return $original->(@_) };
    }
}
my $app = Dancer::Handler->get_handler->psgi_app;
test_psgi $app, sub {
    my $request = shift;
    my $put = sub {
        my ($user, $session, $type) = @_;
        %calls = ();
        return $request->(PUT 'http://localhost/api/'.($type // 'endeduser').'/'.$user->id,
            Cookie => 'session_id='.$session->id, Content => [real_name => 'Ended session write']);
    };
    my $refused = sub {
        my ($user, $session, $name, $type) = @_;
        my $res = $put->($user, $session, $type);
        is $res->code, 401, "$name session is refused";
        is decode_json($res->content)->{error}{message}, 'You must log in to do that.', "$name returns the login error";
        is_deeply \%calls, {}, "$name stops before model verification or mutation";
        ok !defined Wing->cache->get($session->key), "$name session cache entry is removed";
        $user->discard_changes;
        isnt $user->real_name, 'Ended session write', "$name did not persist the write";
    };

    for my $sso (1, 0) {
        my $user = make_user("ended-expired-$sso");
        my $session = make_session($user, sso => $sso);
        my $data = Wing->cache->get($session->key);
        $data->{absolute_expires_at} = time - 60;
        Wing->cache->set($session->key, $data);
        $refused->($user, $session, "absolute-expired sso=$sso");

        $user = make_user("ended-password-$sso");
        $session = make_session($user, sso => $sso);
        $user->encrypt_and_set_password('changed-password');
        $user->update;
        $refused->($user, $session, "password-changed sso=$sso");
    }

    my $user = make_user('ended-denied-expired');
    my $session = make_session($user, sso => 1);
    my $data = Wing->cache->get($session->key);
    $data->{absolute_expires_at} = time - 60;
    Wing->cache->set($session->key, $data);
    $refused->($user, $session, 'absolute-expired without the permission', 'denieduser');

    $user = make_user('ended-denied-password');
    $session = make_session($user, sso => 1);
    $user->encrypt_and_set_password('changed-password');
    $user->update;
    $refused->($user, $session, 'password-changed without the permission', 'denieduser');

    $user = make_user('active-denied');
    $session = make_session($user, sso => 1);
    my $before = Wing->cache->get($session->key)->{extended};
    my $denied = $put->($user, $session, 'denieduser');
    is $denied->code, 450, 'active session without the permission is denied';
    is(Wing->cache->get($session->key)->{extended}, $before, 'denied request does not renew the session');

    for my $admin (0, 1) {
        $user = make_user("deactivated-$admin");
        $user->admin($admin);
        $user->update;
        $session = make_session($user, sso => 1);
        $user->permanently_deactivated(1);
        $user->update;
        my $res = $put->($user, $session);
        is $res->code, 450, "deactivated admin=$admin session is refused";
        is decode_json($res->content)->{error}{message}, 'Account permanently deactivated', "deactivated admin=$admin returns the deactivation error";
        is(Wing->cache->get($session->key)->{extended}, 1, "deactivated admin=$admin session is not renewed");
    }

    Wing::Session->add_validator(sub { ($_[0]->auth_source // '') ne 'revoked-by-app' });
    my $revoked_user = make_user('ended-app-revoked');
    my $revoked = make_session($revoked_user);
    my $revoked_data = Wing->cache->get($revoked->key);
    $revoked_data->{auth_source} = 'revoked-by-app';
    Wing->cache->set($revoked->key, $revoked_data);
    $refused->($revoked_user, $revoked, 'app-rejected');

    $user = make_user('ended-renewed');
    $session = make_session($user);
    my $extended = Wing->cache->get($session->key)->{extended};
    my $res = $put->($user, $session);
    is $res->code, 200, 'active session is authorized' or diag $res->content;
    ok $calls{update}, 'active session reaches the model';
    is(Wing->cache->get($session->key)->{extended}, $extended + 1, 'active session is renewed');
    $user->discard_changes;
    is $user->real_name, 'Ended session write', 'active session write persists';

    my $probe = sub { ($helper_input, $helper_permissions) = @_; return decode_json($request->(GET 'http://localhost/helper-input-probe')->content)->{result} };
    my $object_user = make_user('ended-object');
    my $object_session = make_session($object_user);
    is $probe->($object_session), 'user '.$object_user->id, 'a session object resolves its user';
    is $probe->($object_user), 'error 401', 'a user object is not accepted as a session';
    $object_session->end;
    is $probe->($object_session), 'error 401', 'an ended session object is refused';

    my $held_user = make_user('ended-held-object');
    my $held = make_session($held_user);
    Wing::Session->new(id => $held->id, db => Wing->db)->end;
    is $probe->($held), 'error 401', 'a held session object ended through another instance is refused';

    my $denied_user = make_user('denied-object');
    is $probe->(make_session($denied_user), ['ended_unheld_permission']), 'error 450', 'a session object without the permission is denied';

    my $deactivated_user = make_user('deactivated-object');
    my $deactivated = make_session($deactivated_user);
    $deactivated_user->permanently_deactivated(1);
    $deactivated_user->update;
    is $probe->($deactivated), 'error 401', 'a session object of a deactivated user is refused';
};

my $user = make_user('ended-direct');
my $session = make_session($user);
my $data = Wing->cache->get($session->key);
$data->{absolute_expires_at} = time - 60;
Wing->cache->set($session->key, $data);
my $loaded = Wing::Session->new(id => $session->id, db => Wing->db);
ok !defined $loaded->extend, 'extend reports the ended session';
ok !$loaded->has_user_id, 'ended session clears its user id';
ok !defined $loaded->user, 'ended session resolves no user';
$session->end;
ok !$session->has_user_id && !defined $session->user, 'end clears an already resolved user';

my $shared = make_user('ended-shared');
my @sessions = map { make_session($shared) } 1, 2;
$shared->permanently_deactivated(1);
$shared->update;
ok !defined Wing::Session->new(id => $sessions[0]->id, db => Wing->db)->extend, 'first session of a deactivated user ends';
ok !defined Wing::Session->new(id => $sessions[1]->id, db => Wing->db)->extend, 'second session of a deactivated user also ends';

done_testing;

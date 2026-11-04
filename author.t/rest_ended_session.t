use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Wing;
use Wing::Rest;
use Wing::Session;
use Plack::Test;
use Dancer::Handler;
use HTTP::Request::Common qw(PUT);
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
        my ($user, $session) = @_;
        %calls = ();
        return $request->(PUT 'http://localhost/api/endeduser/'.$user->id,
            Cookie => 'session_id='.$session->id, Content => [real_name => 'Ended session write']);
    };
    my $refused = sub {
        my ($user, $session, $name) = @_;
        my $res = $put->($user, $session);
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

    my $badge_user = make_user('ended-badge');
    Wing->cache->set('floor-active-login-'.$badge_user->id, {floorLoginId => 'floor-1'});
    my $badge = make_session($badge_user, auth_source => 'floor_badge', floor_login_id => 'floor-1');
    Wing->cache->remove('floor-active-login-'.$badge_user->id);
    $refused->($badge_user, $badge, 'revoked floor badge');

    my $user = make_user('ended-renewed');
    my $session = make_session($user);
    my $extended = Wing->cache->get($session->key)->{extended};
    my $res = $put->($user, $session);
    is $res->code, 200, 'active session is authorized' or diag $res->content;
    ok $calls{update}, 'active session reaches the model';
    is(Wing->cache->get($session->key)->{extended}, $extended + 1, 'active session is renewed');
    $user->discard_changes;
    is $user->real_name, 'Ended session write', 'active session write persists';
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

done_testing;

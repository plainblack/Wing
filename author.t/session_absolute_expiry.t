use strict;
use warnings;
use Test::More;
use lib 'lib';
use Wing::Session;

{
    package Local::SessionCache;

    sub new {
        return bless { values => {}, ttls => {} }, shift;
    }

    sub get {
        my ($self, $key) = @_;
        return $self->{values}{$key};
    }

    sub set {
        my ($self, $key, $value, $ttl) = @_;
        $self->{values}{$key} = $value;
        $self->{ttls}{$key} = $ttl;
        return 1;
    }

    sub remove {
        my ($self, $key) = @_;
        delete $self->{values}{$key};
        delete $self->{ttls}{$key};
        return 1;
    }
}

{
    package Local::SessionUser;

    sub new { return bless {}, shift }
    sub id { return 'user-1' }
    sub password { return 'password-hash' }
    sub permanently_deactivated { return 0 }
    sub current_session { return }
    sub user_to_json { return { id => 'user-1' } }
}

{
    package Local::SessionDb;
}

my $cache = Local::SessionCache->new;
my $user = Local::SessionUser->new;
my $absolute_expires_at = time + 4 * 60 * 60;
$cache->set(
    'floor-active-login-user-1',
    { floorLoginId => 'floor-login-1', sessionIds => [] },
    4 * 60 * 60,
);

{
    no warnings qw(redefine once);
    local *Wing::cache = sub { return $cache };

    my $session = Wing::Session->new(
        id => 'floor-session',
        db => bless({}, 'Local::SessionDb'),
    );
    $session->start($user, {
        sso => 0,
        ip_address => '127.0.0.1',
        auth_source => 'floor_badge',
        floor_login_id => 'floor-login-1',
        absolute_expires_at => $absolute_expires_at,
    });

    my $stored = $cache->get('session-floor-session');
    is($stored->{auth_source}, 'floor_badge', 'stores the badge authentication source');
    is($stored->{floor_login_id}, 'floor-login-1', 'stores the originating Floor login');
    is(
        $stored->{absolute_expires_at},
        $absolute_expires_at,
        'stores the absolute session expiration',
    );
    cmp_ok(
        $cache->{ttls}{'session-floor-session'},
        '<=',
        4 * 60 * 60,
        'does not cache the session beyond the absolute expiration',
    );

    my $reloaded = Wing::Session->new(
        id => 'floor-session',
        db => bless({}, 'Local::SessionDb'),
    );
    is($reloaded->auth_source, 'floor_badge', 'reloads the authentication source');
    is($reloaded->floor_login_id, 'floor-login-1', 'reloads the Floor login id');
    is(
        $reloaded->absolute_expires_at,
        $absolute_expires_at,
        'reloads the absolute expiration',
    );

    $reloaded->user($user);
    $reloaded->extend;
    is(
        $cache->get('session-floor-session')->{absolute_expires_at},
        $absolute_expires_at,
        'preserves the absolute expiration when legacy traffic extends the session',
    );

    $cache->remove('floor-active-login-user-1');
    my $revoked = Wing::Session->new(
        id => 'floor-session',
        db => bless({}, 'Local::SessionDb'),
    );
    ok(!$revoked->has_user_id, 'rejects a badge session after its Floor login is revoked');
    ok(!$cache->get('session-floor-session'), 'removes the revoked badge session');
}

done_testing;

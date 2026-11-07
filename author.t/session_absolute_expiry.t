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
    sub get_columns { return (id => 'user-1') }
}

{
    package Local::SessionDb;

    sub resultset { return shift }
    sub find { return Local::SessionUser->new }
}

my $cache = Local::SessionCache->new;
my $user = Local::SessionUser->new;
my $absolute_expires_at = time + 4 * 60 * 60;
my $db = bless({}, 'Local::SessionDb');

{
    no warnings qw(redefine once);
    local *Wing::cache = sub { return $cache };

    my $session = Wing::Session->new(id => 'badge-session', db => $db);
    $session->start($user, {
        sso => 0,
        ip_address => '127.0.0.1',
        auth_source => 'badge',
        floor_login_id => 'login-1',
        absolute_expires_at => $absolute_expires_at,
    });

    my $stored = $cache->get('session-badge-session');
    is($stored->{auth_source}, 'badge', 'stores the authentication source');
    is($stored->{floor_login_id}, 'login-1', 'stores the application login id');
    is(
        $stored->{absolute_expires_at},
        $absolute_expires_at,
        'stores the absolute session expiration',
    );
    cmp_ok(
        $cache->{ttls}{'session-badge-session'},
        '<=',
        4 * 60 * 60,
        'does not cache the session beyond the absolute expiration',
    );

    my $reloaded = Wing::Session->new(id => 'badge-session', db => $db);
    is($reloaded->auth_source, 'badge', 'reloads the authentication source');
    is($reloaded->floor_login_id, 'login-1', 'reloads the application login id');
    is(
        $reloaded->absolute_expires_at,
        $absolute_expires_at,
        'reloads the absolute expiration',
    );
    $reloaded->user($user);
    ok($reloaded->is_valid, 'a session validates with no registered validator');

    $reloaded->extend;
    is(
        $cache->get('session-badge-session')->{absolute_expires_at},
        $absolute_expires_at,
        'preserves the absolute expiration when legacy traffic extends the session',
    );

    my $password = Wing::Session->new(id => 'password-session', db => $db);
    $password->start($user, { sso => 0, ip_address => '127.0.0.1' });

    my @seen;
    Wing::Session->add_validator(sub {
        my ($candidate) = @_;
        push @seen, $candidate->id;
        return ($candidate->auth_source // '') ne 'badge';
    });

    ok(!$session->is_valid, 'a registered validator rejects an in-memory session');
    ok(!$session->has_user_id, 'the rejected in-memory session is ended');
    ok(!$cache->get('session-badge-session'), 'the rejected session is removed from the cache');

    $cache->set('session-badge-session', {
        session_id => 'badge-session',
        user_id => 'user-1',
        password_hash => 'password-hash',
        auth_source => 'badge',
    });
    @seen = ();
    my $cached = Wing::Session->new(id => 'badge-session', db => $db);
    is_deeply(\@seen, ['badge-session'], 'the validator receives the loaded session');
    ok(!$cached->has_user_id, 'a registered validator rejects a cached session');
    ok(!$cache->get('session-badge-session'), 'the rejected cached session is removed');

    my $reloaded_password = Wing::Session->new(id => 'password-session', db => $db);
    ok($reloaded_password->is_valid, 'sessions the validator accepts stay valid');

    ok(!eval { Wing::Session->add_validator('not code'); 1 }, 'refuses a validator that is not code');
    like($@ && $@->message, qr/code reference/, 'explains what a validator must be');
}

done_testing;

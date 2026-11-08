package Wing::Session;

use Moose;
use Wing::Perl;
use Data::GUID;
use URI::Escape;
use Ouch;
use JSON;
use Wing::Util qw/is_in/;

sub key {
    my $self = shift;
    return 'session-'.$self->id;
}

has db => (
    is          => 'ro',
    required    => 1,
);

has id => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        return Data::GUID->new->as_string;
    },
);

sub BUILD {
    my $self = shift;
    my $session_data = Wing->cache->get($self->key);
    if (defined $session_data && ref $session_data eq 'HASH') {
        if ($self->id ne $session_data->{session_id}) {
            Wing->log->fatal(sprintf('SESSION ID CONFLICT 1: Session %s fetched data for session %s containing user %s', $self->id, $session_data->{session_id}, $session_data->{user_id}));
            my $other_data = Wing->cache->get('session-'.$session_data->{session_id});
            Wing->log->debug(sprintf('SESSION ID CONFLICT 2: Looking up the other session %s resulted in session %s containing user %s', $session_data->{session_id}, $other_data->{session_id}, $other_data->{user_id}));
            if ($self->id eq $other_data->{session_id}) {
                Wing->log->info(sprintf('SESSION ID CONFLICT 3a: Was able to replace primary lookup with secondary lookup for session %s on user %s.', $other_data->{session_id}, $other_data->{user_id}));
                $session_data = $other_data;
            }
            else {
                Wing->log->info(sprintf('SESSION ID CONFLICT 3b: Was NOT able to take corrective action for original session %s with secondary session %s.', $session_data->{session_id}, $other_data->{session_id}));
                Wing->cache->remove($self->key);
                ouch 401, 'An error occured that required us to log you out. Log back in and try again.';
            }
        }
        $self->password_hash($session_data->{password_hash});
        $self->user_id($session_data->{user_id});
        $self->extended($session_data->{extended});
        $self->ip_address($session_data->{ip_address});
        $self->sso($session_data->{sso});
        $self->api_key_id($session_data->{api_key_id});
        $self->auth_source($session_data->{auth_source}) if exists $session_data->{auth_source};
        $self->floor_login_id($session_data->{floor_login_id}) if exists $session_data->{floor_login_id};
        $self->absolute_expires_at($session_data->{absolute_expires_at}) if exists $session_data->{absolute_expires_at};
        $self->end unless $self->passes_validators;
    }
}

has extended => (
    is          => 'rw',
    default     => 0,
);

has api_key_id => (
    predicate   => 'has_api_key_id',
    is          => 'rw',
);

has ip_address => (
    is          => 'rw',
);

has sso => (
    is          => 'rw',
    default     => 0,
);

has auth_source => (
    is          => 'rw',
    predicate   => 'has_auth_source',
);

has floor_login_id => (
    is          => 'rw',
    predicate   => 'has_floor_login_id',
);

has absolute_expires_at => (
    is          => 'rw',
    predicate   => 'has_absolute_expires_at',
);

has user_id => (
    is          => 'rw',
    predicate   => 'has_user_id',
    clearer     => 'clear_user_id',
    trigger     => sub {
        my $self = shift;
        $self->clear_user;
    },
);

has password_hash => (
    is          => 'rw',
    predicate   => 'has_password_hash',
);

has user => (
    is          => 'rw',
    predicate   => 'has_user',
    clearer     => 'clear_user',
    lazy        => 1,
    default     => sub {
        my $self = shift;
        return undef unless $self->has_user_id;
        my $user = $self->cached_user;
        if (defined $user && ! $user->permanently_deactivated) {
            $user->current_session($self);
        }
        return $user;
    },
);

# While a user's change marker is set its row may be uncommitted or cached stale, so read it from the database.
sub cached_user {
    my $self = shift;
    my $data_key = 'user-data-' . $self->user_id;
    my $changed_key = 'user-changed-' . $self->user_id;
    if (Wing->cache->get($changed_key)) {
        Wing->cache->remove($data_key);
        return $self->db->resultset('User')->find($self->user_id);
    }
    my $data = Wing->cache->get($data_key);
    if (ref $data eq 'HASH') {
        my $source = $self->db->source('User');
        return $source->result_class->inflate_result($source, $data);
    }
    # A shared lock waits for any uncommitted change, so only committed rows are cached.
    my $user = $self->db->resultset('User')->find($self->user_id, { for => 'shared' });
    return $user unless defined $user;
    Wing->cache->set($data_key, { $user->get_columns }, 60 * 60 * 24 * 7);
    # A change that landed during the read may have removed the entry before this write.
    Wing->cache->remove($data_key) if Wing->cache->get($changed_key);
    return $user;
}

sub get_permissions {
    my $self = shift;
    my @permissions = $self->db->resultset('APIKeyPermission')->search({
        user_id     => $self->user_id,
        api_key_id  => $self->api_key_id,
    })
    ->get_column('permission')
    ->all;
    return \@permissions;
}

sub check_permissions {
    my ($self, $permissions) = @_;
    return 1 unless $self->sso; # always has permissions if this isn't a single-sign-on session
    return 1 if (!defined $permissions || ref $permissions ne 'ARRAY' || !scalar(@{$permissions})); # has permissions if they aren't asking for any
    unless (defined $self->user) { # can't have permissions if they haven't logged in or their user is gone
        $self->end;
        ouch(401, 'You must log in to access that.',$permissions);
    }
    ouch(450, 'Account permanently deactivated') if $self->user->permanently_deactivated; # Active users only, admins included
    return 1 if $self->user->is_admin; # always has permissions if they're an admin
    ouch(450, 'Insufficient permissions.',$permissions) unless $self->has_api_key_id; # can't have permissions if they didn't assign an API key
    my $existing = $self->get_permissions;
    foreach my $permission (@{$permissions}) {
        unless (is_in($permission, $existing || [])) {
            ouch(450, 'Insufficient permissions.',$permissions);
        }
    }
    return 1;
}

my @validators;

# Registers a code reference that receives the session and returns false when the application wants it ended.
sub add_validator {
    my ($class, $validator) = @_;
    ouch 500, 'Wing::Session->add_validator needs a code reference, such as \&My::App::session_is_active.' unless ref $validator eq 'CODE';
    push @validators, $validator;
    return;
}

sub passes_validators {
    my $self = shift;
    for my $validator (@validators) {
        return 0 unless $validator->($self);
    }
    return 1;
}

# Ends the session and returns false when it has expired, an application validator rejects it, its user is gone or its password changed.
sub is_valid {
    my $self = shift;
    if (!$self->passes_validators
        || ($self->has_absolute_expires_at && int($self->absolute_expires_at - time) <= 0)) {
        $self->end;
        return 0;
    }

    if (!defined $self->user) {
        $self->end;
        return 0;
    }
    if ($self->password_hash ne $self->user->password) {
        Wing->log->debug("SESSION: Password hashes do not match, ending session for user id:". $self->user->id);
        Wing->log->debug("SESSION: Password hash sample: ".substr($self->password_hash,0,5));
        Wing->log->debug("SESSION: Password user sample: ".substr($self->user->password,0,5));
        $self->end;
        return 0;
    }
    return 1;
}

sub extend {
    my $self = shift;
    return unless $self->is_valid;
    if ($self->user->permanently_deactivated) {
        $self->end;
        return;
    }

    my $ttl = 60 * 60 * 24 * 7;
    if ($self->has_absolute_expires_at) {
        my $remaining = int($self->absolute_expires_at - time);
        $ttl = $remaining if $remaining < $ttl;
    }
    $self->extended( $self->extended + 1 );
    my $session_data = {
            password_hash    => $self->password_hash, # this hash is stored here so that if the user changes their password we can log out all existing sessions
            user_id     => $self->user_id,
            extended    => $self->extended,
            sso         => $self->sso,
            api_key_id  => $self->api_key_id,
            ip_address  => $self->ip_address,
            session_id  => $self->id,
    };
    $session_data->{auth_source} = $self->auth_source if $self->has_auth_source;
    $session_data->{floor_login_id} = $self->floor_login_id if $self->has_floor_login_id;
    $session_data->{absolute_expires_at} = $self->absolute_expires_at if $self->has_absolute_expires_at;
    Wing->cache->set($self->key, $session_data, $ttl);
    return $self;
}

sub is_human {
    my $self = shift;
    if (Wing->cache->get($self->id.'_is_human')) {
        return 1;
    }
    ouch 455, 'Must verify humanity.';
}

sub end {
    my $self = shift;
    Wing->cache->remove($self->key);
    $self->clear_user;
    $self->clear_user_id;
    return $self;
}

sub start {
    my ($self, $user, $options) = @_;
    $self->user_id($user->id);
    $self->password_hash($user->password);
    $user->current_session($self);
    $self->user($user);
    $self->sso($options->{sso});
    $self->ip_address($options->{ip_address});
    $self->api_key_id($options->{api_key_id});
    $self->auth_source($options->{auth_source}) if exists $options->{auth_source};
    $self->floor_login_id($options->{floor_login_id}) if exists $options->{floor_login_id};
    $self->absolute_expires_at($options->{absolute_expires_at}) if exists $options->{absolute_expires_at};
    return $self->extend;
}

sub describe {
    my ($self, %options) = @_;
    my $out = {
        id          => $self->id,
        object_type => 'session',
        object_name => 'Session',
        user_id     => $self->user_id,
    };
    if ($options{include_private} || (exists $options{current_user} && defined $options{current_user} && $options{current_user} eq $self->user_id)) {
        $out->{extended} = $self->extended;
        $out->{ip_address} = $self->ip_address;
        $out->{sso} = $self->sso;
    }
    if ($options{include_relationships}) {
        $out->{_relationships}{user} = '/api/user/'.$self->user_id;
        $out->{_relationships}{self} = '/api/session/'.$self->id;
    }
    if ($options{include_related_objects}) {
        $out->{user} = $self->user->describe;
    }
    return $out;
}

no Moose;
__PACKAGE__->meta->make_immutable;

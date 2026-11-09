package Wing::SSO;

use Moose;
use Wing::Perl;
use String::Random qw(random_string);
use Wing::Util qw/is_in/;

has db => (
    is          => 'ro',
    required    => 1,
);

has id => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        my $foo = String::Random->new;
        $foo->{'A'} = [ 'A'..'Z', 'a'..'z', 0..9 ];
        return $foo->randpattern('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA');
    },
);

sub BUILD {
    my $self = shift;
    my $data = Wing->cache->get('sso'.$self->id);
    if (defined $data && ref $data eq 'HASH') {
        $self->user_id($data->{user_id});
        $self->ip_address($data->{ip_address});
        $self->api_key_id($data->{api_key_id});
        $self->postback_uri($data->{postback_uri});
        $self->requested_permissions($data->{requested_permissions});
        $self->consented($data->{consented});
    }
}

has postback_uri => (
    is          => 'rw',
);

has consented => (
    is          => 'rw',
);

has requested_permissions => (
    is          => 'rw',
    isa         => 'ArrayRef',
    default     => sub { [] },
);

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

sub supported_requested_permissions {
    my $self = shift;
    my $available = Wing->config->get('api_key_permissions');
    return [grep { defined $_ && is_in($_, $available) } @{$self->requested_permissions}];
}

sub has_requested_permissions {
    my $self = shift;
    my $existing = $self->get_permissions;
    return 0 unless scalar @{$existing}; # a key the user never approved always gets the consent form
    foreach my $permission (@{$self->supported_requested_permissions}) {
        return 0 unless is_in($permission, $existing);
    }
    return 1;
}

sub grant_requested_permissions {
    my $self = shift;        
    my $permissions = $self->db->resultset('APIKeyPermission');
    foreach my $request (@{$self->supported_requested_permissions}) {
        my $permission = $permissions->new({});
        $permission->user_id($self->user_id);
        $permission->api_key_id($self->api_key_id);
        $permission->permission($request);
        $permission->insert;
    }
}

has api_key_id => (
    is          => 'rw',
    predicate   => 'has_api_key_id',
    trigger     => sub {
        my $self = shift;
        $self->clear_api_key;
    },
);

has api_key => (
    is          => 'rw',
    predicate   => 'has_api_key',
    clearer     => 'clear_api_key',
    lazy        => 1,
    default     => sub {
        my $self = shift;
        return undef unless $self->has_api_key_id;
        return $self->db->resultset('APIKey')->find($self->api_key_id);
    },
);

has ip_address=> (
    is          => 'rw',
);

has user_id => (
    is          => 'rw',
    predicate   => 'has_user_id',
    trigger     => sub {
        my $self = shift;
        $self->clear_user;
    },
);

has user => (
    is          => 'rw',
    predicate   => 'has_user',
    clearer     => 'clear_user',
    lazy        => 1,
    default     => sub {
        my $self = shift;
        return undef unless $self->has_user_id;
        return $self->db->resultset('User')->find($self->user_id);
    },
);

sub delete {
    my $self = shift;
    Wing->cache->remove('sso'.$self->id);
    return $self;
}

sub store {
    my $self = shift;
    Wing->cache->set(
        'sso'.$self->id,
        {
            user_id                 => $self->user_id,
            api_key_id              => $self->api_key_id,
            postback_uri            => $self->postback_uri,
            ip_address              => $self->ip_address,
            consented               => $self->consented,
            requested_permissions   => $self->requested_permissions,
        },
        { expires_in => 60 * 60 },
    );
    return $self;
}

sub consent {
    my $self = shift;
    $self->consented(1);
    return $self->store;
}

sub redirect {
    my ($self) = @_;
    if ($self->postback_uri eq 'native') {
        return '/sso/success?sso_id='.$self->id;
    }
    else {
        my $uri = $self->postback_uri;
        $uri .= ($uri =~ m/\?/) ? '&' : '?';
        $uri .= 'sso_id='.$self->id;
        return $uri;
    }
}

no Moose;
__PACKAGE__->meta->make_immutable;

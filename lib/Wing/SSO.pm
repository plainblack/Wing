package Wing::SSO;

use Moose;
use Wing::Perl;
use Data::GUID;

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
    my $data = Wing->cache->get('sso'.$self->id);
    if (defined $data && ref $data eq 'HASH') {
        $self->user_id($data->{user_id});
        $self->ip_address($data->{ip_address});
        $self->api_key_id($data->{api_key_id});
        $self->postback_uri($data->{postback_uri});
    }
}

has postback_uri => (
    is          => 'rw',
);

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
        { user_id => $self->user_id, api_key_id => $self->api_key_id, postback_uri => $self->postback_uri, ip_address => $self->ip_address },
        { expires_in => 60 * 60 },
    );
    return $self;
}

sub redirect {
    my ($self) = @_;
    my $uri = $self->postback_uri;
    $uri .= ($uri =~ m/\?/) ? '&' : '?';
    $uri .= 'sso_id='.$self->id;
    return $uri;
}

no Moose;
__PACKAGE__->meta->make_immutable;

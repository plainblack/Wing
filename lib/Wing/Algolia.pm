package Wing::Algolia;

use Wing;
use Wing::Perl;
use Moo;
use LWP::UserAgent;
use HTTP::Request::Common qw(PUT DELETE POST);
use Encode qw(encode_utf8);
use JSON;

sub BUILDARGS {
    my $class = shift;
    my %args = (@_, %{Wing->config->get('algolia')});
    return \%args;
}

has application_id => (
    is      => 'ro',
    required=> 1,
);

has api_key => (
    is      => 'ro',
    required=> 1,
);

has public_key => (
    is      => 'ro',
    required=> 1,
);

has base_url => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        my $self = shift;
        return 'https://' . $self->application_id . '.algolia.io/1';
    }
);

has headers => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        my $self = shift;
        return {
            'X-Algolia-Application-Id' => $self->application_id,
            'X-Algolia-API-Key' => $self->api_key,
        };
    }
);

sub replace_index_object {
    my ($self, $index, $id, $data) = @_;
    my $url = join('/', $self->base_url, 'indexes', $index, $id);
    my $json = JSON->new;
    return $self->handle_response(PUT $url, %{$self->headers}, ( content => encode_utf8($json->encode($data)) ));
}

sub update_index_settings {
    my ($self, $index, $data) = @_;
    my $url = join('/', $self->base_url, 'indexes', $index, 'settings');
    my $json = JSON->new;
    return $self->handle_response(PUT $url, %{$self->headers}, ( content => encode_utf8($json->encode($data)) ));
}

sub delete_index_object {
    my ($self, $index, $id) = @_;
    my $url = join('/', $self->base_url, 'indexes', $index, $id);
    my $json = JSON->new;
    return $self->handle_response(DELETE $url, %{$self->headers});
}

sub delete_index {
    my ($self, $index) = @_;
    my $url = join('/', $self->base_url, 'indexes', $index);
    my $json = JSON->new;
    return $self->handle_response(DELETE $url, %{$self->headers});
}

sub clear_index {
    my ($self, $index, $id) = @_;
    my $url = join('/', $self->base_url, 'indexes', $index, 'clear');
    my $json = JSON->new;
    return $self->handle_response(POST $url, %{$self->headers});
}

sub handle_response {
    my ($self, $request) = @_;
    #say $request->as_string;
    my $ua = LWP::UserAgent->new(timeout => 10);
    my $response = $ua->request($request);
    die $response->status_line unless $response->is_success; 
    return 1 unless $response->content;
    return $response->content;
}


1;

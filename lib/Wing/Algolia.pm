package Wing::Algolia;

use Wing;
use Wing::Perl;
use Moo;
use LWP::UserAgent;
use HTTP::Request::Common qw(PUT DELETE POST);
use Encode qw(encode_utf8);
use JSON;
no strict 'refs';

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
        return 'https://' . $self->application_id . '.algolia.net/1';
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
    return $self->make_request('PUT', ['indexes', $index, $id], $data);
}

sub update_index_settings {
    my ($self, $index, $data) = @_;
    return $self->make_request('PUT', ['indexes', $index, 'settings'], $data);
}

sub delete_index_object {
    my ($self, $index, $id) = @_;
    return $self->make_request('DELETE', ['indexes', $index, $id]);
}

sub delete_index {
    my ($self, $index) = @_;
    return $self->make_request('DELETE', ['indexes', $index]);
}

sub clear_index {
    my ($self, $index, $id) = @_;
    return $self->make_request('POST', ['indexes', $index, 'clear']);
}

sub make_request {
    my ($self, $method, $url_parts, $data) = @_;
    my %encoded_data = ();
    if ($data) {
        my $json = JSON->new;
	%encoded_data = ( content => encode_utf8($json->encode($data)));
    }
    my $request = $method->(join('/', $self->base_url, @{$url_parts}), %{$self->headers}, %encoded_data);
    #say $request->as_string;
    my $ua = LWP::UserAgent->new(timeout => 10);
    my $response = $ua->request($request);
    if (! $response->is_success) {
        Wing->log->error("ALGOLIA FAILURE");
        Wing->log->error("Request: ". $request->as_string);
        Wing->log->error("Response: ". $response->as_string);
        die "Error updating search index\n";
    }
    return 1 unless $response->content;
    return $response->content;
}


1;

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

has url_options => (
    is      => 'ro',
    default => sub { [
	'.algolia.net',
	'-1.algolianet.com',
	'-2.algolianet.com',
	'-3.algolianet.com',
    ] },
);

has url_index => (
    is      => 'rw',
    default => 0,
);

has base_url => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        my $self = shift;
        return $self->url_options->[$self->url_index];
    },
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
    my ($self, $method, $url_parts, $data, $retry_count) = @_;
    $retry_count //= 0;
    my %encoded_data = ();
    if ($data) {
        my $json = JSON->new;
	%encoded_data = ( content => encode_utf8($json->encode($data)));
    }
    my $request = $method->(join('/', 'https://'.$self->application_id.$self->base_url, 1, @{$url_parts}), %{$self->headers}, %encoded_data);
    #say $request->as_string;
    my $ua = LWP::UserAgent->new(timeout => 10);
    my $response = $ua->request($request);
    if (! $response->is_success) {
	my $url_option_count = scalar(@{$self->url_options});
	if ($retry_count >= $url_option_count) {
		Wing->log->error("ALGOLIA FAILURE");
		Wing->log->debug("Request: ". $request->as_string);
		Wing->log->debug("Response: ". $response->as_string);
		die "Error updating search index\n";
        }
        else {
		Wing->log->info('Retrying algolia write with new host.');
		$self->url_index($self->url_index+1);
		if ($self->url_index >= $url_option_count) {
			$self->url_index(0);
		}
 		return $self->make_request($method, $url_parts, $data, $retry_count + 1);
        }
    }
    return 1 unless $response->content;
    return $response->content;
}


1;

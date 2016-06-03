package Wing::TestHelper;

use Dancer;
use Dancer::Request;
use Dancer::Test appdir => '../lib';
use Plack::Test;
use Dancer::Handler;
use Ouch;
use Scalar::Util qw/blessed/;
use HTTP::Request::Common;

use Wing;
use Wing::Perl;
use Wing::Rest::Session;
use Wingman;
use Moose;

has debug_enabled => (
    is      => 'rw',
    default => 0,
);

has user => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        my $self = shift;
        my $users = Wing->db->resultset('User');
        my $andy = $users->find({username => 'andy'});
        unless (defined $andy) {
            $andy = $users->new({
                username    => 'andy',
                real_name   => 'Andy Dufresne',
                email       => 'andy@shawshank.jail',
                admin       => 1,
                developer   => 1,
                use_as_display_name => 'real_name', 
            });
            $andy->encrypt_and_set_password('Saywatanayo');
            $andy->insert;    
        }
        $self->add_to_cleanup($andy);
        return $andy;
    }
);

has apikey => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        my $self = shift;
        my $keys = Wing->db->resultset('APIKey');
        my $key = $keys->find({name => 'Key for Andy'});
        unless (defined $key) {
            $key = $keys->new({user_id => $self->user->id, name => 'Key for Andy', });
            $key->insert;
        }
        $self->add_to_cleanup($key);
        return $key;
    }
);

sub get_session {
    my $self = shift;
    return $self->rest('POST','/api/session', { username => 'andy', password => 'Saywatanayo', api_key_id => $self->apikey->id, _include_related_objects => 1 });
}

has things_to_cleanup => (
    is      => 'rw',
    default => sub { [] },
);

sub add_to_cleanup {
    my $self = shift;
    push @{$self->things_to_cleanup}, [@_];
}

sub wait_on_wingman {
    my $self = shift;
        my $timeout = 0;
        print "Waiting for Wingman processes to complete";
        while ($timeout < 60) {
            my $stats = Wingman->new->stats_as_hashref;
            if ($stats->{current_jobs_ready} + $stats->{current_jobs_reserved} + $stats->{current_jobs_urgent} + $stats->{current_jobs_delayed} == 0) {
                last;
            }
            print ".";
            sleep 1;
            $timeout++;
        }
        print "\n";
}

sub cleanup_wait_on_wingman {
    my $self = shift;
    $self->add_to_cleanup(sub {
        $self->wait_on_wingman;
    });
}

sub rest {
    my ($self, $method, $path, $params) = @_;
    ouch(441, 'You must set a method of GET/POST/PUT/DELETE to test a REST call.') unless $method;
    ouch(441, 'You must set a path to test a REST call.') unless $path;
    $ENV{REMOTE_ADDR} = '127.0.0.1';
    $ENV{HTTP_USER_AGENT} = 'WingTestHelper';
    say "REQUEST:" if $self->debug_enabled; 
    say $method.' '.$path if $self->debug_enabled;
    say to_json($params) if $self->debug_enabled;
    my $content = exists $params->{file} ? $self->rest_via_plack_test($method, $path, $params) : $self->rest_via_dancer_test($method, $path, $params);
    say "RESPONSE:" if $self->debug_enabled; 
    say $content if $self->debug_enabled;
    my $out = eval{from_json($content)};
    ouch(500, "got garbage back from ".$method." ".$path." (".to_json($params)."): ".$content) if ($@);
    if (exists $out->{error}) {
        ouch $out->{error}{code}, $out->{error}{message}, $out->{error}{data};
    }
    return $out;
}

sub rest_via_dancer_test {
    my ($self, $method, $path, $params) = @_;
    my $response = eval{dancer_response $method => $path, { params => $params }};
    say bleep if $@;
    return $response->{content};
}

sub rest_via_plack_test { # for file uploads
    my ($self, $method, $path, $params) = @_;
    my $app = Dancer::Handler->get_handler->psgi_app;
    my $content;
    test_psgi $app, sub {
        my $cb = shift;
        my $request = POST $path, Content_Type => 'form-data', Content => [%{$params}];
        $request->method($method);
        my $response = $cb->($request);
        $content = $response->content;
    };
    return $content;
}

sub cleanup {
    my $self = shift;
    foreach my $thing (reverse @{$self->things_to_cleanup}) {
        if (ref $thing->[0] eq 'CODE') {
            $thing->[0]->();
        }
        elsif (ref $thing->[0]) {
            eval { 
                if ($self->debug_enabled) {
                    say "Cleaning up ".ref($thing->[0])." with id ".$thing->[0]->id;
                }
                $thing->[0]->delete;
            };
            if ($@) {
                say "Could not delete ".ref($thing->[0])." with id ".$thing->[0]->id." because ".bleep($@);
            }
        }
        elsif ($thing->[0] && $thing->[1]) {
            my $object = Wing->db->resultset($thing->[0])->find($thing->[1]);
            if (defined $object) {
                if ($self->debug_enabled) {
                    say "Cleaning up ".$thing->[0]." with id ".$thing->[1];
                }
                $object->delete;
                if ($@) {
                    say "Could not delete ".$thing->[0]." with id ".$thing->[1]." because ".bleep($@);
                }
            }
        }
        else {
            say "Don't know how to clean up ".$thing->[0];
        }
    }
}


1;

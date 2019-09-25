package Wing::Firebase;

use Wing;
use Moo;

extends 'Firebase';
use Encode;
use Time::HiRes;
use Text::Demoroniser qw/demoroniser_utf8/;

around BUILDARGS => sub {
    my $orig = shift;
    my $class = shift;
    my $config = Wing->config->get('firebase');
    my %args = (@_, firebase => $config->{database}, auth => $config->{auth});
    return $class->$orig(%args);
};

has directory => (
    is => 'rw',
    default => sub { 'status' },
);

sub object_status {
    my $self      = shift;
    my $object    = shift;
    my $directory = join '/', $self->directory, $object->id, int(Time::HiRes::time()*1000);
    my $payload   = shift;
    if (ref($payload) eq 'HASH' && exists $payload->{message}) {
        $payload->{message} = demoroniser_utf8($payload->{message});
    }
    utf8::upgrade($payload->{message});
    utf8::encode($payload->{message});
    return $self->put($directory, $payload, @_);
}

1;

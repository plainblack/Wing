package Wing::Firebase;

use Wing;
use Moo;

extends 'Firebase';
use Time::HiRes;

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
    return $self->put($directory, @_);
}

1;

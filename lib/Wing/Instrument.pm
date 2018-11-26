package Wing::Instrument;

use Wing::Perl;
use Wing;
use Moo;
use Time::HiRes;
use JSON;

has id => (
    is => 'rw',
    default => sub { time() },
);

has sensitivity => (
    is => 'rw',
    default => 1,
);

has recordings => (
    is => 'rw',
    default => sub { [] },
);

has start => (
    is => 'ro',
    default => sub { [Time::HiRes::gettimeofday] },
);

sub interval {
    my $self = shift;
    Time::HiRes::tv_interval($self->start)
}

sub record {
   my ($self, $name) = @_;
   push @{$self->recordings}, { $name => $self->interval };
}

sub as_json {
    my $self = shift;
    return encode_json($self->recordings);
}

sub log {
    my ($self, $label) = @_;
    Wing->log->warn(sprintf('INSTRUMENT: %s (%s) = %s', $label, $self->id, $self->as_json)) if $self->interval > $self->sensitivity;
}

1;

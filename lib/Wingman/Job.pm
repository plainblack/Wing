package Wingman::Job;

use Wing::Perl;
use Moose;
with 'Wingman::Role::Logger';

has beanstalk_job => (
    is      => 'ro',
    required=> 1,
    isa     => 'Beanstalk::Job',
    handles => [qw(id buried reserved delete touch peek release bury ttr priority)],
);

has wingman_plugin => (
    is      => 'ro',
    required=> 1,
);

has job_args => (
    is      => 'ro',
    required=> 1,
    isa     => 'HashRef',
);

sub run {
    my ($self) = @_;
    $self->log_info($self, 'Running job');
    my $out = eval { $self->wingman_plugin->run($self->job_args) };
    if ($@) {
        $self->log_error($self, 'Error running plugin: '.$@);
        $self->bury;
    }
    else {
        $self->log_info($self, 'Job complete.');
        $self->delete;
        return $out;
    }
}

1;

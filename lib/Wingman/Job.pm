package Wingman::Job;

=head1 NAME

Wingman::Job - A single job in the Wingman work queue.

=head1 SYNOPSIS

 my $job = $wingman->next_job();
 my $id = $job->id;
 $job->delete;
 $job->run;

=head1 DESCRIPTION

This object reveals all the things you can do with a Wingman job.

=head1 METHODS

=head2 new

Constructor. You should never call this yourself. Use methods from L<Wingman> to generate a C<Wingman::Job>.

=cut

use Wing::Perl;
use Moose;
use Ouch;
with 'Wingman::Role::Logger';

has beanstalk_job => (
    is      => 'ro',
    required=> 1,
    isa     => 'Beanstalk::Job',
    handles => [qw(id buried reserved delete touch peek release bury ttr priority stats)],
);

=head2 Pass Through Methods

The following methods pass through directly from L<Beanstalk::Job>.

=over

=item id

=item buried

=item reserved

=item delete

=item touch

=item peek

=item release

=item bury

=item ttr

=item priority

=item stats

=back

=cut

has wingman_plugin => (
    is      => 'ro',
    required=> 1,
);

has job_args => (
    is      => 'ro',
    required=> 1,
    isa     => 'HashRef',
);

=head2 run

Executes this job. Normally you'd want to let the C<run> method in L<Wingman> do this. But this is useful for testing, or running one off commmands.

Will L<Ouch> if the plugin fails for any reason.

Returns the output of the plugin, if any. Note that this is only useful for testing, as the actual L<Wingman> task master doesn't do anything with it.

=cut

sub run {
    my ($self) = @_;
    $self->log_info($self, 'Running job');
    my $out = eval { $self->wingman_plugin->run($self, $self->job_args) };
    if ($@) {
        $self->log_error($self, 'Error running plugin: '.$@);
        $self->bury;
        ouch 500, $@;
    }
    else {
        $self->log_info($self, 'Job complete.');
        return $out;
    }
}

=head2 stats_as_hashref ()

Does the same thing as C<stats> except returns a hashref of the stats instead of the L<Beanstalk:Stats> object.

=cut

sub stats_as_hashref {
    my ($self) = @_; 
    my $stats = $self->stats;
    my %beanstalk;
    foreach my $key (keys %{$stats}) {
        my $underscore_key = $key;
        $underscore_key =~ s/-/_/g;
        $beanstalk{$underscore_key} = $stats->{$key};
    }
    return \%beanstalk;
}

=head2 describe ( )

Returns a hash reference with all the relevant details of the job.

=cut

sub describe {
    my $self = shift;
    my $class = ref $self->wingman_plugin;
    my %out = (
        %{$self->stats_as_hashref},
        phase       => Wing->config->get('wingman/plugins/'.$class.'/phase'),
        arguments   => $self->job_args,
    );
    return \%out;
}


1;

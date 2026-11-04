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

Will L<Ouch> if the plugin throws an exception.

Returns the output of the plugin unchanged. Legacy returns without C<wingman_outcome>
keep their existing completion behavior. Plugins that check queue acknowledgements
should return a hash with C<wingman_outcome> set to one of:

=over

=item complete

The plugin confirmed its terminal queue acknowledgement.

=item retained

The plugin intentionally retained the job under its own recovery policy.

=item failed

The queue outcome failed or is uncertain. Include a human-readable C<message>
explaining the failure and operator recovery instruction. The framework logs an
error with the job ID, returns the result, and does not delete, bury, release or
retry the job itself. This is a logging outcome, not a retention acknowledgement.
A reserved job can become ready again when the worker disconnects or its TTR
expires. The plugin must establish and confirm its own terminal or retention
policy before returning if redelivery would be unsafe. Catch acknowledgement
exceptions inside the plugin and return this outcome when ordinary exception
burial would violate its recovery policy.

=back

Unknown outcomes are logged as errors. Retained and failed outcomes never log
C<Job complete.>. The worker remains responsible for choosing and confirming its
queue operation; this contract does not provide exactly-once external effects.

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
        if (ref($out) eq 'HASH' && exists $out->{wingman_outcome}) {
            my $outcome = $out->{wingman_outcome};
            if (defined $outcome && $outcome eq 'retained') {
                $self->log_info($self, 'Job retained.');
                return $out;
            }
            if (!defined $outcome || $outcome ne 'complete') {
                my $message = defined $outcome && $outcome eq 'failed'
                    ? (defined $out->{message} && !ref($out->{message}) && length $out->{message}
                        ? $out->{message} : 'A failed outcome requires a nonempty message with operator recovery instructions.')
                    : 'Invalid wingman_outcome; use complete, retained or failed.';
                $self->log_error($self, 'Job '.$self->id.' failed: '.$message
                    .' Confirm the plugin terminal or retention acknowledgement; otherwise the broker may redeliver on worker disconnect or TTR expiry.');
                return $out;
            }
        }
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

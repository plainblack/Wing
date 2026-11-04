package Wingman::Role::EmailRecovery;

use Wing::Perl;
use Wing;
use Moose::Role;

around run => sub {
    my ($run, $self, $job, $args) = @_;
    my $prepared = eval {
        my $stats = $job->stats;
        die "Cannot inspect job tube. Check broker connectivity.\n" unless $stats;
        my $tube = $stats->tube;
        my $excluded = Wing->config->get('wingman/autokick_excluded_tubes');
        die "Add tube $tube to wingman/autokick_excluded_tubes before running email jobs.\n"
            unless ref($excluded) eq 'ARRAY'
                && !(grep { !defined $_ || ref $_ || !length $_ } @$excluded)
                && (grep { $_ eq $tube } @$excluded);
        # Retain before irreversible effects so disconnect and TTR cannot resend mail.
        $job->bury or die "Burial not acknowledged. Check broker connectivity before retrying.\n";
        1;
    };
    return { wingman_outcome => 'failed', message => "Email delivery not started: $@ Check configuration and broker state before retrying." }
        unless $prepared;

    my $delivered = eval { $self->$run($job, $args); 1 };
    my $error = $@;
    unless ($delivered) {
        return { wingman_outcome => 'failed', message =>
            "Email delivery or fan-out failed: $error Reconcile SMTP acceptance and published child jobs before manually deleting or retrying the buried job; partial delivery is possible." };
    }
    my $deleted = eval { $job->delete };
    $error = $@;
    return { wingman_outcome => 'complete' } if $deleted;
    return { wingman_outcome => 'failed', message =>
        'Final email job deletion not acknowledged. '
        . ($error || $job->beanstalk_job->error || 'No deletion response.')
        . ' Reconcile SMTP acceptance and published child jobs with this job ID before manually deleting it. Do not kick or resend without reconciliation. Burial was acknowledged before delivery; inspect broker state because deletion may have succeeded despite a lost response.' };
};

1;

=head1 NAME

Wingman::Role::EmailRecovery - Manual recovery for irreversible email work.

=head1 DESCRIPTION

SendTemplatedEmail and EmailAllAdmins require their actual job tube to be listed
in C<wingman/autokick_excluded_tubes>. Configure this on every worker and
C<autokick_jobs> host before running these plugins. An absent or invalid setting
prevents delivery. Use a dedicated email tube if other work needs automatic
retry; pass C<wingman_job_options> when publishing background email.

The plugin confirms burial before SMTP or child publication and checks final
deletion. A failed or throwing deletion returns C<failed>, never acknowledged
completion. Burial prevents broker redelivery on worker disconnect or TTR expiry,
but does not prevent explicit kicks, external recovery tools, broker data loss,
or an operator changing the exclusion configuration. Keep broker persistence
configured to meet the application's durability requirements.

A crash at any point after burial can leave an unsent, partially sent, or fully
sent job buried. Reconcile the logged job ID against SMTP acceptance records and,
for fan-out, child publications before deleting or selectively resuming work.
Do not blindly kick a parent: it can republish all children. A missing deletion
response may mean deletion succeeded. Inspect the broker before any recovery.
This policy provides neither automatic retry nor exactly-once SMTP delivery.

=cut

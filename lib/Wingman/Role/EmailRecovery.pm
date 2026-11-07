package Wingman::Role::EmailRecovery;

use Wing::Perl;
use Moose::Role;

around run => sub {
    my ($run, $self, $job, $args) = @_;
    my $prepared = eval {
        # Retain before irreversible effects so disconnect and TTR cannot resend mail.
        $job->bury or die "Burial not acknowledged. Check broker connectivity before retrying.\n";
        1;
    };
    return { wingman_outcome => 'failed', message => "Email delivery not started: $@ Check broker state before retrying." }
        unless $prepared;

    my $delivered = eval { $self->$run($job, $args); 1 };
    my $error = $@;
    return _alert_buried($job,
        "Email delivery or fan-out failed: $error Reconcile SMTP acceptance and published child jobs before manually deleting or retrying the buried job; partial delivery is possible.")
        unless $delivered;
    my $deleted = eval { $job->delete };
    $error = $@;
    return { wingman_outcome => 'complete' } if $deleted;
    return _alert_buried($job,
        'Final email job deletion not acknowledged. '
        . ($error || $job->beanstalk_job->error || 'No deletion response.')
        . ' Reconcile SMTP acceptance and published child jobs with this job ID before manually deleting it. Do not kick or resend without reconciliation. Burial was acknowledged before delivery; inspect broker state because deletion may have succeeded despite a lost response.');
};

sub _alert_buried {
    my ($job, $message) = @_;
    # Sent directly, not queued, so the alert does not wait behind the failing email tube.
    my $alerted = eval {
        Wing->send_templated_email('stuck_wingman_job', {
            email   => Wing->config->get('wing_admin'),
            subject => 'Wingman email job '.$job->id.' failed and is buried',
        });
        1;
    };
    $message .= ' Emailing the wing_admin alert also failed: '.$@.' Check the SMTP settings.' unless $alerted;
    return { wingman_outcome => 'failed', message => $message };
}

1;

=head1 NAME

Wingman::Role::EmailRecovery - Manual recovery for irreversible email work.

=head1 DESCRIPTION

SendTemplatedEmail and EmailAllAdmins send queued email whatever their tube and
whatever the autokick configuration. An installation with neither
C<wingman/email_tube> nor C<wingman/autokick_excluded_tubes> sends queued email
on its default tube. C<autokick_jobs> never kicks the email tube
(C<wingman/email_tube>, or the default tube when that is unset) or a buried
email job in any other tube. A dedicated email tube keeps email's manual
recovery apart from other work, so the default tube can be kicked again. New
installations queue email on the default tube; to use a dedicated tube, set:

 "wingman": {
     "email_tube": "wingman.email",
     "autokick_excluded_tubes": ["wingman.email"]
 }

Merge these keys into the existing Wing JSON configuration. Keep the existing
C<beanstalkd/default_tube> for unrelated work. L<Wingman/put> documents routing
precedence. C<wingman_job_options =E<gt> { tube =E<gt> "custom.mail" }> still
selects an explicit destination; watch that actual tube too.
Synchronous email and other plugins retain their existing behavior.

Default C<wingman.pl> workers now watch both the default and configured email
tubes. Explicit lists replace the defaults: use
C<wing wingman --restart --watch=wingman,wingman.email> or
C<wingman.pl restart --watch-only=wingman,wingman.email> for those names.
Include any host-specific or other required tubes as well. Every email tube
must have a worker with its email plugins loaded.

For existing installations, first deploy the routing-aware worker code and
restart workers with both the old and new tubes watched. Exclude the new tube
from autokick on every autokick host before publishers use C<email_tube>. Then
set C<email_tube> consistently on all publishers and workers. Keep the old email
tube excluded until its existing jobs are drained or manually reconciled.
Inspect ready, delayed, reserved and buried jobs before removing that old
exclusion. Already queued jobs never move. Buried email must never be
automatically kicked. No running configuration is changed automatically. Leaving the setting absent
or null preserves legacy routing.

The plugin confirms burial before SMTP or child publication and checks final
deletion. A failed or throwing deletion returns C<failed>, never acknowledged
completion. Burial prevents broker redelivery on worker disconnect or TTR expiry,
but does not prevent explicit kicks, external recovery tools, broker data loss,
or an operator changing the autokick exclusion configuration. Keep broker persistence
configured to meet the application's durability requirements.

A crash at any point after burial can leave an unsent, partially sent, or fully
sent job buried. Reconcile the logged job ID against SMTP acceptance records and,
for fan-out, child publications before deleting or selectively resuming work.
Do not blindly kick a parent: it can republish all children. A missing deletion
response may mean deletion succeeded. Inspect the broker before any recovery.
This policy provides neither automatic retry nor exactly-once SMTP delivery.

When delivery, fan-out or the final deletion fails, the job stays buried and the
plugin emails C<wing_admin> the C<stuck_wingman_job> alert at once, with the job ID
in its subject. If that alert cannot be sent either, the failure message says so.
SendTemplatedEmail treats a bad address (Ouch 442, including a permanent SMTP
recipient refusal) as final: it logs a warning
and the job is deleted.

=cut

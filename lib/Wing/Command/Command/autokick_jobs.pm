package Wing::Command::Command::autokick_jobs;

use Wing;
use Wing::Perl;
use Wing::Command -command;
use Wingman;

sub abstract { 'Monitor buried Wingman jobs without retrying them.' }

sub usage_desc { 'Monitor buried Wingman jobs without retrying them.' }

sub opt_spec {
    return (
    );
}

sub validate_args {
    my ($self, $opt, $args) = @_;
    # no args allowed but options!
    $self->usage_error("No args allowed, only options.") if @$args;
}

sub execute {
    my ($self, $opt, $args) = @_;
    Wing->log->info('Monitoring buried Wingman jobs; automatic retries belong to their plugins.');

    my $excluded = Wing->config->get('wingman/autokick_excluded_tubes');
    die "wingman/autokick_excluded_tubes must be an array of non-empty tube names.\n"
        if defined $excluded && (ref $excluded ne 'ARRAY'
            || grep { !defined $_ || ref $_ || !length $_ } @$excluded);
    my %excluded = map { $_ => 1 } @{defined $excluded ? $excluded : []};

    my $wingman = Wingman->new();
    my @tubes = $wingman->list_tubes;

    my $has_stuck_jobs = 0;
    my @monitoring_errors;

    foreach my $tube (@tubes) {
        my $stats = $wingman->stats_tube($tube);
        unless (defined $stats) {
            my $error = $wingman->error;
            next if defined $error && $error eq 'NOT_FOUND';
            push @monitoring_errors, "Cannot monitor buried jobs in $tube"
                . (defined $error && length $error ? ": $error" : '')
                . ". Check the broker and rerun autokick_jobs.\n";
            next;
        }
        my $buried = $stats->current_jobs_buried;
        next unless $buried;
        Wing->log->info("Buried backlog in $tube: $buried jobs. Inspect job IDs and reconcile effects before selective manual recovery.");
        $has_stuck_jobs = 1 unless $excluded{$tube};
        if ($buried > 1) {
            $has_stuck_jobs = 1;
            Wing->log->info("Retained backlog in $tube: $buried buried jobs; cannot determine ages or retry counts behind the head. Inspect retained jobs for manual recovery.");
        }
        # Inspect broker metadata without decoding the payload or loading its plugin.
        my $head;
        if ($wingman->use($tube)) {
            $head = $wingman->beanstalk->peek_buried;
        }
        unless (defined $head) {
            my $error = $wingman->error;
            next if defined $error && $error eq 'NOT_FOUND';
            push @monitoring_errors, "Cannot inspect buried head in $tube"
                . (defined $error && length $error ? ": $error" : '')
                . ". Check the broker and rerun autokick_jobs.\n";
            next;
        }
        my $head_stats = $wingman->stats_job($head->id);
        unless (defined $head_stats) {
            my $error = $wingman->error;
            next if defined $error && $error eq 'NOT_FOUND';
            push @monitoring_errors, "Cannot inspect buried job ".$head->id." in $tube"
                . (defined $error && length $error ? ": $error" : '')
                . ". Check the broker and rerun autokick_jobs.\n";
            next;
        }
        Wing->log->info("Buried head ".$head->id." in $tube: age ".$head_stats->age." seconds, ".$head_stats->kicks." kicks.");
        if ($head_stats->kicks > 1) {
            $has_stuck_jobs = 1;
            Wing->log->info("Stuck job ".$head->id." in $tube");
        }
        elsif ($head_stats->age > 12*60*60) {
            $has_stuck_jobs = 1;
            Wing->log->info("Old job ".$head->id." in $tube");
        }
    }

    if ($has_stuck_jobs) {
        Wing->log->info('Emailing admin about Wingman jobs needing inspection.');
        Wing->send_templated_email('stuck_wingman_job', { email => Wing->config->get('wing_admin'), subject => 'Wingman jobs need inspection', });
    }

    die join('', @monitoring_errors) if @monitoring_errors;
}

1;

=head1 NAME

wing autokick_jobs - Monitor buried Wingman jobs

=head1 SYNOPSIS

 wing autokick_jobs

=head1 DESCRIPTION

This historical command name now performs read-only monitoring. It never kicks,
reserves, releases, buries or deletes a job. Buried jobs require selective manual
recovery after their effects and failure cause have been inspected. Existing
buried backlogs are not automatically migrated or retried.

Each visible Wingman tube reports its buried count and available head statistics.
An ordinary tube with any buried work requests administrator inspection. Tubes
in C<wingman/autokick_excluded_tubes> retain their quieter monitoring policy:
more than one buried job, a head kicked more than once, or a head older than
12 hours triggers the alert. Hidden job ages and retry counts are unknown.
Foreign Jobber tubes remain outside Wingman's scope. Payloads are not decoded
and plugins are not loaded by monitoring.

Keep C<wingman/autokick_excluded_tubes> configured for email/manual recovery;
email plugins still require their actual tube in this array before sending.
Invalid lists stop monitoring visibly. Broker errors do not suppress other tubes
or already detected alerts, and the command fails visibly after reporting them.

Automatic retries belong to the plugin: classify an identified temporary failure,
check persistent C<stats-E<gt>reserves> before performing effects, and confirm a
positive-delay C<release> of the same job while its attempt budget permits.
The plugin owns exhaustion handling and operator reporting. Unknown exceptions,
C<failed>/C<retained> outcomes and false legacy returns are not retry requests.
See L<Wingman::Role::Plugin> and the retry rollout section in C<TESTING.md>.

=head1 OPTIONS

None.

=head1 AUTHOR

Copyright 2017 Plain Black Corporation.

=cut

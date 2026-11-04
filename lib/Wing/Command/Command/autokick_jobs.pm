package Wing::Command::Command::autokick_jobs;

use Wing;
use Wing::Perl;
use Wing::Command -command;
use Data::Dumper;
use Wingman;

sub abstract { 'Autokick jobs in the Wingman tube.' }

sub usage_desc { 'Autokick jobs in the Wingman tube.' }

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
    Wing->log->info('Kicking stuck wingman jobs.');

    my $excluded = Wing->config->get('wingman/autokick_excluded_tubes');
    die "wingman/autokick_excluded_tubes must be an array of non-empty tube names.\n"
        if defined $excluded && (ref $excluded ne 'ARRAY'
            || grep { !defined $_ || ref $_ || !length $_ } @$excluded);
    my %excluded = map { $_ => 1 } @{defined $excluded ? $excluded : []};

    my $wingman = Wingman->new();
    my @tubes = $wingman->list_tubes;

    ##Stuck jobs are jobs that have been buried two or more times
    ##and kicked at least once.  Let JT know so they can be fixed.
    ##Also monitor jobs that have been in the tube for a long time.
    my $has_stuck_jobs = 0;
    my %seen_jobs = ();
    my @monitoring_errors;

    TUBE: foreach my $tube (@tubes) {
        Wing->log->info('Looking for stuck wingman jobs in '.$tube);
        if ($excluded{$tube}) {
            my $stats = $wingman->stats_tube($tube);
            unless (defined $stats) {
                my $error = $wingman->error;
                next TUBE if defined $error && $error eq 'NOT_FOUND';
                push @monitoring_errors, "Cannot monitor retained tube $tube"
                    . (defined $error && length $error ? ": $error" : '')
                    . ". Check the broker and rerun autokick_jobs.\n";
                next TUBE;
            }
            my $buried = $stats->current_jobs_buried;
            if ($buried > 1) {
                $has_stuck_jobs = 1;
                Wing->log->info("Retained backlog in $tube: $buried buried jobs; cannot determine ages or retry counts behind the head. Inspect retained jobs for manual recovery.");
            }
        }
        JOB: while (my $job = $wingman->peek_buried($tube)) {
            next TUBE unless $job;
            ##If there's only one job, this will loop forever, so keep track of what we've seen
            ##and move on to the next tube.
            next TUBE if $seen_jobs{$job->id}++;
            if ($job->stats->kicks > 1) {
                $has_stuck_jobs = 1;
                Wing->log->info("Stuck job ".$job->id." in $tube");
                next JOB;
            }
            elsif ($job->stats->age > 12*60*60) {
                $has_stuck_jobs = 1;
                Wing->log->info("Old job ".$job->id." in $tube");
                next JOB;
            }
            else {
                next TUBE if $excluded{$tube};
                $wingman->kick_job($job->id);
                Wing->log->info("Kicking job ".$job->id." in $tube");
            }
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

wing autokick_jobs - Kick jobs that are in Wingman

=head1 SYNOPSIS

 wing autokick_jobs

=head1 DESCRIPTION

Using this command you can automatically kick Wingman jobs in a beanstalkd tube.  If jobs were kicked more than once, or have been in the tube for longer
than 12 hours, then an email will be sent to the address in the Wing config file, C<wing_admin>.

To retain buried jobs for manual recovery, set C<wingman/autokick_excluded_tubes>
in the Wing JSON configuration to an array of exact tube names:

 "wingman": {
     "autokick_excluded_tubes": ["stitcher.orders"]
 }

Merge this setting into the existing C<wingman> object. Omit it or use an empty
array to keep automatic recovery for every visible Wingman tube. Each entry must
be a non-empty tube name. Invalid configuration stops the command before any
queue changes. Excluded tubes are still checked for stuck and old buried jobs
and can still trigger the administrator email. If an excluded tube has more than
one buried job, it also triggers the email and logs the tube's buried-job count
with a request for manual inspection. Beanstalkd exposes only the buried head,
so ages and retry counts of jobs behind it are unknown. This backlog alert fires
even when the head is fresh and the hidden jobs may also be fresh. A single
fresh retained job does not trigger an alert. No retained jobs are mutated to
inspect them. This setting affects
only C<autokick_jobs>; explicit manual recovery commands remain available.
Foreign Jobber tubes remain outside Wingman's scope.

=head1 OPTIONS

None.

=head1 AUTHOR

Copyright 2017 Plain Black Corporation.

=cut

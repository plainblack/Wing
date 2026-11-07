package Wing::Command::Command::autokick_jobs;

use Wing;
use Wing::Perl;
use Wing::Command -command;
use Wingman;

sub abstract { 'Kick fresh buried Wingman jobs and alert about stuck ones.' }

sub usage_desc { 'Kick fresh buried Wingman jobs and alert about stuck ones.' }

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
    Wing->log->info('Kicking buried Wingman jobs.');

    my $excluded = Wing->config->get('wingman/autokick_excluded_tubes');
    die "wingman/autokick_excluded_tubes must be an array of non-empty tube names.\n"
        if defined $excluded && (ref $excluded ne 'ARRAY'
            || grep { !defined $_ || ref $_ || !length $_ } @$excluded);
    my %excluded = map { $_ => 1 } @{defined $excluded ? $excluded : []};
    # Email plugins bury before sending, so a kick could send the same email twice.
    $excluded{Wingman->email_tube // Wing->config->get('wingman/beanstalkd/default_tube') // 'default'} = 1;

    my $wingman = Wingman->new();
    my %email_phase = map { $_ => 1 } $wingman->email_phases;
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
        Wing->log->info("Buried backlog in $tube: $buried jobs.");
        my $retained = $excluded{$tube};
        if ($retained && $buried > 1) {
            $has_stuck_jobs = 1;
            Wing->log->info("Retained backlog in $tube: $buried buried jobs; cannot determine ages or retry counts behind the head. Inspect retained jobs for manual recovery.");
        }
        my %seen;
        # Beanstalkd only exposes the buried head, so a job that must stay buried is moved behind the others.
        JOB: for my $position (1 .. ($retained ? 1 : $buried)) {
            my $head;
            if (defined $wingman->use($tube)) {
                $head = $wingman->beanstalk->peek_buried;
            }
            unless (defined $head) {
                my $error = $wingman->error;
                last JOB if defined $error && $error eq 'NOT_FOUND';
                push @monitoring_errors, "Cannot inspect buried head in $tube"
                    . (defined $error && length $error ? ": $error" : '')
                    . ". Check the broker and rerun autokick_jobs.\n";
                last JOB;
            }
            my $id = $head->id;
            last JOB if $seen{$id}++;
            my $head_stats = $wingman->stats_job($id);
            unless (defined $head_stats) {
                my $error = $wingman->error;
                last JOB if defined $error && $error eq 'NOT_FOUND';
                push @monitoring_errors, "Cannot inspect buried job $id in $tube"
                    . (defined $error && length $error ? ": $error" : '')
                    . ". Check the broker and rerun autokick_jobs.\n";
                last JOB;
            }
            Wing->log->info("Buried head $id in $tube: age ".$head_stats->age." seconds, ".$head_stats->kicks." kicks.");
            my ($phase) = $retained ? () : eval { $head->args };
            my $email = defined $phase && $email_phase{$phase};
            my $problem = $head_stats->kicks > 1 ? "Stuck job $id in $tube"
                : $head_stats->age > 12*60*60 ? "Old job $id in $tube"
                : $retained ? undef
                : !defined $phase ? "Unreadable job $id in $tube"
                : $email && $position < $buried ? "Buried email job $id in $tube holds back the buried jobs behind it"
                : undef;
            if ($problem) {
                $has_stuck_jobs = 1;
                Wing->log->info($problem);
            }
            # Email is never reserved either: losing the reservation would make it ready and send it again.
            last JOB if $retained || $email;
            unless ($problem) {
                unless ($wingman->kick_job($id)) {
                    next JOB if ($wingman->error // '') eq 'NOT_FOUND';
                    push @monitoring_errors, "Cannot kick buried job $id in $tube: ".($wingman->error // 'no broker response')
                        . ". Check the broker and rerun autokick_jobs.\n";
                    last JOB;
                }
                Wing->log->info("Kicked job $id in $tube");
                next JOB;
            }
            last JOB if $position == $buried;
            unless ($wingman->reserve_job($id)) {
                next JOB if ($wingman->error // '') eq 'NOT_FOUND';
                push @monitoring_errors, "Cannot move buried job $id in $tube behind the other buried jobs: "
                    . ($wingman->error // 'no broker response')
                    . ". Jobs behind it were not kicked. Check that beanstalkd is 1.12 or later and rerun autokick_jobs.\n";
                last JOB;
            }
            unless ($wingman->bury($id, { priority => $head_stats->pri })) {
                push @monitoring_errors, "Job $id in $tube was reserved to move it but could not be buried again: "
                    . ($wingman->error // 'no broker response')
                    . ". It returns to ready when autokick_jobs exits, so inspect it before a worker runs it.\n";
                last JOB;
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

wing autokick_jobs - Kick buried Wingman jobs

=head1 SYNOPSIS

 wing autokick_jobs

=head1 DESCRIPTION

Kicks fresh buried jobs so they run again. A job kicked more than once, or buried
for longer than 12 hours, stays buried and sends an email to C<wing_admin>, as
does a job whose payload cannot be read. Such a job is moved behind the other
buried jobs in its tube (beanstalkd C<reserve-job>, then C<bury> with its
priority) so the fresh jobs behind it are still kicked. This needs beanstalkd 1.12
or later.

Email jobs are never kicked, because the email plugins bury a job before sending
and a kick could send it twice. The tube email is published to
(C<wingman/email_tube>, or C<wingman/beanstalkd/default_tube> when that is unset)
is always treated as excluded. A buried SendTemplatedEmail, EmailAllAdmins or
EmailAllUsers job in any other tube is left buried and never reserved; like an
excluded tube, it alerts when it is stuck or old, or when other buried jobs wait
behind it, since they cannot be kicked until it is resolved.

To retain buried jobs for manual recovery, list their tubes in
C<wingman/autokick_excluded_tubes>:

 "wingman": {
     "autokick_excluded_tubes": ["stitcher.orders"]
 }

Each entry must be a non-empty tube name; invalid configuration stops the command
before any queue changes. Excluded tubes are never kicked and their payloads are
not read. They alert when they hold more than one buried job (ages and retry
counts behind the head are unknown), or when the head was kicked more than once
or is older than 12 hours. A single fresh retained job does not alert.

Foreign Jobber tubes remain outside Wingman's scope. Broker errors do not suppress
other tubes or already detected alerts, and the command fails visibly after
reporting them.

=head1 OPTIONS

None.

=head1 AUTHOR

Copyright 2017 Plain Black Corporation.

=cut

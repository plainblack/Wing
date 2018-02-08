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

    my $wingman = Wingman->new();
    my @tubes = $wingman->list_tubes;

    ##Stuck jobs are jobs that have been buried two or more times
    ##and kicked at least once.  Let JT know so they can be fixed.
    ##Also monitor jobs that have been in the tube for a long time.
    my $has_stuck_jobs = 0;
    my %seen_jobs = ();

    TUBE: foreach my $tube (@tubes) {
        Wing->log->info('Looking for stuck wingman jobs in '.$tube);
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
                $wingman->kick_job($job->id);
                Wing->log->info("Kicking job ".$job->id." in $tube");
            }
        }
    }

    if ($has_stuck_jobs) {
        Wing->log->info('Emailing admin about stuck wingman jobs.');
        Wing->send_templated_email('stuck_wingman_job', { email => Wing->config->get('wing_admin'), subject => 'Stuck Wingman jobs', });
    }

}

1;

=head1 NAME

wing autokick_jobs - Kick jobs that are in Wingman

=head1 SYNOPSIS

 wing autokick_jobs

=head1 DESCRIPTION

Using this command you can automatically kick Wingman jobs in a beanstalkd tube.  If jobs were kicked more than once, or have been in the tube for longer
than 12 hours, then an email will be sent to the address in the Wing config file, wing_admin_email.

=head1 OPTIONS

None.

=head1 AUTHOR

Copyright 2017 Plain Black Corporation.

=cut

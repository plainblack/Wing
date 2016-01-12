package Wing::Command::Command::kick;

use Wing;
use Wing::Perl;
use Wing::Command -command;
use Ouch;
use Wingman;
use JSON;

sub abstract { 'kick buried Wingman jobs' }

sub usage_desc { 'Kick buried Wingman jobs from the command line.' }

sub description { 'Examples:
wing kick 

'};

sub opt_spec {
    my $config = Wing->config->get('wingman/beanstalkd');
    return (
      [ 'tube=s', 'tube to kick. kicks all tubes by default', { default => undef } ],
    );
}

sub execute {
    my ($self, $opt, $args) = @_;
    my $wingman = Wingman->new;
    my $has_stuck_jobs = 0;
    my %seen_jobs = ();
    my @tubes;
    if ($opt->{tube}) {
        push @tubes, $opt->{tube};
    }
    else {
        @tubes = $wingman->list_tubes;
    }
    TUBE: foreach my $tube (@tubes) {
        JOB: while (my $job = $wingman->peek_buried($tube)) {
            next TUBE unless $job;
            ##If there's only one job, this will loop forever, so keep track of what we've seen
            ##and move on to the next tube.
            next TUBE if $seen_jobs{$job->id}++;
            if ($job->stats->kicks > 1) {
                $has_stuck_jobs++;
                say "Stuck job ".$job->id." in $tube";
            }
            say "Kicking job ".$job->id." in $tube";
            $wingman->kick_job($job->id);
        }
    }
    say "Kicked all buried jobs.";

    if ($has_stuck_jobs) {
        say "There were $has_stuck_jobs stuck jobs that should be investigated.";
    }
}

1;

=head1 NAME

wing kick - Kick buried Wingman jobs.

=head1 SYNOPSIS

 wing kick

 wing kick --tube=some_tube_name

=head1 DESCRIPTION

This will let you kick all the stuck jobs in your wingman tubes. It's mostly useful for a dev environment when you've broken something and now that you've fixed it you want to set it off again.

=head1 AUTHOR

Copyright 2016 Plain Black Corporation.

=cut

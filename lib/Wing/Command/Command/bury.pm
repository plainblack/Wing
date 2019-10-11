package Wing::Command::Command::bury;

use Wing;
use Wing::Perl;
use Wing::Command -command;
use Ouch;
use Wingman;
use JSON;

sub abstract { 'bury Wingman jobs' }

sub usage_desc { 'bury Wingman jobs from the command line.' }

sub description { 'Examples:
wing bury --job=90782 

'};

sub opt_spec {
    my $config = Wing->config->get('wingman/beanstalkd');
    return (
      [ 'tube=s', 'tube to bury.  all tubes by default', { default => undef } ],
      [ 'job=s', 'job id to bury', { default => undef } ],
    );
}

sub execute {
    my ($self, $opt, $args) = @_;
    unless ($opt->{job}) {
        say 'Need a job';
        return;
    }
    my $wingman = Wingman->new;
    my %seen_jobs = ();
    my $found = 0;
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
            if ($job->id eq $opt->{job}) {
                $job->bury;
                say "Buried job";
                $found = 1;
                last TUBE;
            }
        }
    }

    unless ($found) {
        say "Job ".$opt->{job}." not found";
    }
}

1;

=head1 NAME

wing bury - Bury Wingman jobs.

=head1 SYNOPSIS

 wing bury --job=job_number 

=head1 DESCRIPTION

This will let you bury a specific job.

=head1 AUTHOR

Copyright 2019 Plain Black Corporation.

=cut

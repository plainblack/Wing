package Wing::Command::Command::do;

use Wing;
use Wing::Perl;
use Wing::Command -command;
use Ouch;
use Wingman;
use JSON;

sub abstract { 'create Wingman jobs' }

sub usage_desc { 'Create Wingman jobs from the command line.' }

sub description { 'Examples:
wing do HelloWorld

wing do --delay=60 --priority=9999 HelloWorld 

wing do --priority=500 EmailAllAdmins {\"template\":\"generic\", \"params\":{\"subject\":\"foo\", \"message\":\"bar\"}}

'};

sub opt_spec {
    my $config = Wing->config->get('wingman/beanstalkd');
    return (
      [ 'delay=i', 'number of seconds to wait before adding the job to the waiting queue, default: '.($config->{delay} || 0 ), { default => $config->{delay} || 0 } ],
      [ 'priority=i', 'the relative importance of this job, lower is more important, default: '.($config->{priority} || 2000), { default => $config->{priority} || 2000 } ],
      [ 'ttr=i', 'number of seconds this job has to run, default: '.($config->{ttr} || 60), { default => $config->{ttr} || 60 } ],
      [ 'tube=s', 'tube to put this job in, default: '.($config->{default_tube} || 'wingman'), { default => $config->{default_tube} || 'wingman' } ],
    );
}

sub validate_args {
    my ($self, $opt, $args) = @_;
    # no args allowed but options!
    $self->usage_error("Must at least specify a plugin phase.") unless @$args;
}

sub execute {
    my ($self, $opt, $args) = @_;
    my $phase = shift @{$args};
    my $job_args = join ' ', @{$args}; # just in case they get broken up by the command line parser
    if ($job_args) {
        $job_args = decode_json($job_args);
    }
    else {
        undef $job_args;
    }
    Wingman->new->put($phase, $job_args, $opt);
    say "OK";
}

1;

=head1 NAME

wing do - Launch Wingman jobs.

=head1 SYNOPSIS

 wing do HelloWorld

 wing do --delay=60 --priority=9999 HelloWorld 

 wing do --priority=500 EmailAllAdmins {\"template\":\"generic\", \"params\":{\"subject\":\"foo\", \"message\":\"bar\"}}
 
=head1 DESCRIPTION

We recommend using your operating system's cron scheduler to kick off jobs. You can use this Wing Command to kick off jobs from the command line, and therefore from cron as well.

=head1 AUTHOR

Copyright 2012-2013 Plain Black Corporation.

=cut

#!/usr/bin/env perl

BEGIN {
 die "Must set WING_HOME environment variable." unless $ENV{WING_HOME};
 die "Must set WING_APP environment variable." unless $ENV{WING_APP};
}
use lib $ENV{WING_APP}.'/lib', $ENV{WING_HOME}.'/lib';

use Wingman;
use Wing::Perl;
use Daemon::Control;
use Getopt::Long;

my @tubes;
GetOptions(
    'watch-only=s' =>  sub { push @tubes, split /,/, $_[1] },
);

Daemon::Control->new({
    name        => "Wingman",
    lsb_start   => '$syslog $remote_fs',
    lsb_stop    => '$syslog',
    lsb_sdesc   => 'Wingman is a job server for Wing.',
    lsb_desc    => 'Wingman is a job server for Wing.',
 
    program     => sub { Wingman->new->run( @tubes ); },
 
    pid_file    => Wing->config->get('wingman/pid_file_path') || '/var/run/wingman.pid',
    #stderr_file => '/tmp/mydaemon.out',
    #stdout_file => '/tmp/mydaemon.out',
 
    fork        => 2,
 
})->run;
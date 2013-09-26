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
    'help'              => \my $help,
    'debug-path=s'         => \my $debug,
    'watch-only=s'  =>  sub { push @tubes, split /,/, $_[1] },
);

if ($help) {
    say <<STOP;

    Usage: $0 [ options ]

    --help                              Show this message.

    --debug-path=/tmp/wingman.log       Pipe STDOUT and STDERR to that file.

    --watch-only=foo,bar                Watch some new tubes instead of the default one.

STOP
    exit;
}

my $config = {
    name        => "Wingman",
    lsb_start   => '$syslog $remote_fs',
    lsb_stop    => '$syslog',
    lsb_sdesc   => 'Wingman is a job server for Wing.',
    lsb_desc    => 'Wingman is a job server for Wing.',
 
    program     => sub { Wingman->new->run( @tubes ); },
 
    pid_file    => Wing->config->get('wingman/pid_file_path') || '/var/run/wingman.pid',
 
    fork        => 2,
};

if ($debug) {
    $config->{stderr_file} = $debug;
    $config->{stdout_file} = $debug;
}

Daemon::Control->new($config)->run;

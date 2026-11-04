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
use Parallel::ForkManager;

my @tubes;
my @cli = @ARGV;
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

$0 = 'wingman';

my $pfm;
my $terminate_workers = sub {
    return unless $pfm && $pfm->is_parent;
    $pfm->reap_finished_children;
    kill 15, $pfm->running_procs;
};
my $clean_up_and_shut_down = sub {
    $terminate_workers->();
    $pfm->wait_all_children if $pfm && $pfm->is_parent;
    exit;
};
$SIG{'INT'} = $clean_up_and_shut_down;
$SIG{'TERM'} = $clean_up_and_shut_down;
$SIG{'HUP'} = sub {
    $terminate_workers->();
    return 1;
};

my $config = {
    name        => "Wingman",
    lsb_start   => '$syslog $remote_fs',
    lsb_stop    => '$syslog',
    lsb_sdesc   => 'Wingman is a job server for Wing.',
    lsb_desc    => 'Wingman is a job server for Wing.',
 
    program     => sub {

        $pfm = Parallel::ForkManager->new(Wing->config->get('wingman/max_workers'));
        while (1) {
            my $pid = $pfm->start;
            if ($pid != 0) {    # Parent process
                next;
            }
            my $wingman = Wingman->new;
            $wingman->watch_only(scalar @tubes ? @tubes : Wing->config->get('wingman/beanstalkd/default_tube'));
            $wingman->reserve->run;
            $pfm->finish;
        }
        $pfm->wait_all_children();
        
    },
 
    pid_file    => Wing->config->get('wingman/pid_file_path') || '/var/run/wingman.pid',
 
    fork        => 2,
};

if ($debug) {
    $config->{stderr_file} = $debug;
    $config->{stdout_file} = $debug;
}

Daemon::Control->new($config)->run;

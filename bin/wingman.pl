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
use POSIX qw(SIG_BLOCK SIG_SETMASK SIGINT SIGTERM SIGHUP sigprocmask);

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

    --watch-only=foo,bar                Replace the default and configured email tube watch list.

STOP
    exit;
}

$0 = 'wingman';

my $pfm;
my $manager_pid;
my $terminate_workers = sub {
    return unless $pfm && $$ == $manager_pid && $pfm->max_procs;
    $pfm->reap_finished_children;
    kill 15, $pfm->running_procs;
};
my $clean_up_and_shut_down = sub {
    $terminate_workers->();
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

        $manager_pid = $$;
        $pfm = Parallel::ForkManager->new(Wing->config->get('wingman/max_workers'));
        my $signals = POSIX::SigSet->new(SIGINT, SIGTERM, SIGHUP);
        while (1) {
            $pfm->wait_for_available_procs if $pfm->max_procs;
            my $previous = POSIX::SigSet->new;
            # Defer handlers until the new child is registered in both processes.
            sigprocmask(SIG_BLOCK, $signals, $previous) or die "Cannot block worker signals: $!";
            my $pid = $pfm->start;
            sigprocmask(SIG_SETMASK, $previous) or die "Cannot restore worker signals: $!";
            if ($pid != 0) {    # Parent process
                next;
            }
            my $wingman = Wingman->new;
            my $email_tube = $wingman->email_tube;
            $wingman->watch_only(scalar @tubes ? @tubes
                : (Wing->config->get('wingman/beanstalkd/default_tube'),
                    defined $email_tube ? ($email_tube) : ()));
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

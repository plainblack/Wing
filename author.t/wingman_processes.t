use strict;
use warnings;
use Test::More;
use FindBin;
use POSIX ();

# Application and daemon startup are boundaries; process ownership stays real.
BEGIN {
    package Wingman;
    sub import { }
    $INC{'Wingman.pm'} = __FILE__;
    package ProcessConfig;
    sub get { return 2 if $_[1] eq 'wingman/max_workers'; return '/unused/test-wingman.pid' }
    package Wing;
    sub config { bless {}, 'ProcessConfig' }
    package Daemon::Control;
    our $config;
    sub new { $config = $_[1]; bless {}, $_[0] }
    sub run { }
    $INC{'Daemon/Control.pm'} = __FILE__;
    package main;
    our $signal_at_fork;
    *CORE::GLOBAL::fork = sub {
        my $pid = CORE::fork();
        CORE::kill('HUP', $$) if $pid && $signal_at_fork;
        return $pid;
    };
    *CORE::GLOBAL::exit = sub { die "script exit\n" };
    our @targets;
    our %allowed;
    *CORE::GLOBAL::kill = sub {
        my ($signal, @pids) = @_;
        push @targets, @pids;
        # Never deliver a stale numeric PID to an arbitrary machine process.
        CORE::kill($signal, grep { $allowed{$_} } @pids);
    };
}
use Parallel::ForkManager;
our (@targets, %allowed, @children, $signal_at_fork);
$ENV{WING_HOME} = "$FindBin::Bin/..";
$ENV{WING_APP} = "$FindBin::Bin/..";
local @ARGV;
do "$FindBin::Bin/../bin/wingman.pl";
die $@ if $@;
my $start = Parallel::ForkManager->can('start');
my ($manager, $completed);
{
    no warnings 'redefine';
    local *Parallel::ForkManager::start = sub {
        $manager = $_[0];
        if ($completed) {
            $manager->wait_all_children;
            die "test workers completed\n";
        }
        my $pid = $start->(@_);
        POSIX::_exit(0) unless $pid;
        $completed = $pid;
        return $pid;
    };
    eval { $Daemon::Control::config->{program}->() };
    POSIX::sigprocmask(POSIX::SIG_SETMASK(), POSIX::SigSet->new);
    is $@, "test workers completed\n", 'ran actual parent loop with a real completed worker';
}
is_deeply [$manager->running_procs], [], 'ForkManager has harvested completed worker';
$SIG{HUP}->();
is_deeply \@targets, [], 'reload does not target a completed worker';

# A real process outside this manager models a stale PID now owned elsewhere.
pipe(my $read, my $write) or die $!;
my $sentinel = fork();
die $! unless defined $sentinel;
if (!$sentinel) {
    close $write;
    $SIG{TERM} = 'DEFAULT';
    my $byte;
    sysread($read, $byte, 1);
    POSIX::_exit(0);
}
close $read;
$allowed{$sentinel} = 1;
END {
    if ($sentinel) { CORE::kill('KILL', $sentinel); waitpid($sentinel, 0) }
}
@children = ($sentinel);
@targets = ();
$SIG{HUP}->();
is_deeply \@targets, [], 'reload ignores stale identity outside manager ownership';
ok CORE::kill(0, $sentinel), 'real sentinel remains alive';
close $write;
waitpid($sentinel, 0);
is $?, 0, 'sentinel exited normally through its control pipe';
$sentinel = undef;

$SIG{ALRM} = sub { die "Worker lifecycle test hung; check pipe events\n" };
alarm 30;
my @owned;
END { for my $pid (@owned) { CORE::kill('KILL', $pid); waitpid($pid, 0) } }
sub worker {
    my ($linger) = @_;
    pipe(my $events, my $notify) or die $!;
    pipe(my $release, my $control) or die $!;
    my $pid = $start->($manager);
    unless ($pid) {
        close $events;
        close $control;
        $SIG{TERM} = sub {
            syswrite($notify, 'T');
            POSIX::_exit(0) unless $linger;
        };
        # Inherited reload must not signal the parent's other workers.
        $SIG{HUP}->();
        syswrite($notify, 'R');
        my $byte;
        while (1) {
            my $n = sysread($release, $byte, 1);
            next unless defined $n;
            last;
        }
        POSIX::_exit(0);
    }
    close $notify;
    close $release;
    push @owned, $pid;
    $allowed{$pid} = 1;
    my $byte;
    is sysread($events, $byte, 1), 1, 'worker announces readiness';
    is $byte, 'R', 'worker inherited reload leaves siblings alone';
    return ($pid, $events, $control);
}
my ($live, $events, $control) = worker(1);
pipe(my $identity_read, my $identity_write) or die $!;
my $unregistered = fork();
die $! unless defined $unregistered;
if (!$unregistered) {
    close $identity_read;
    my $warnings = '';
    local $SIG{__WARN__} = sub { $warnings .= $_[0] };
    $SIG{HUP}->();
    syswrite($identity_write, $warnings ? 'W' : 'C');
    POSIX::_exit(0);
}
close $identity_write;
my $identity;
sysread($identity_read, $identity, 1);
waitpid($unregistered, 0);
is $identity, 'C', 'a forked process without the Child role does not reap siblings';
close $identity_read;
for (1..2) {
    @targets = ();
    $SIG{HUP}->();
    is_deeply \@targets, [$live], 'reload retains ownership of a terminating worker';
    my $byte;
    is sysread($events, $byte, 1), 1, 'real worker acknowledges TERM';
    is $byte, 'T', 'TERM reaches the owned process';
}
close $control;
$manager->wait_all_children;
@owned = ();
@targets = ();
$SIG{HUP}->();
is_deeply \@targets, [], 'reload stops targeting the worker after it exits';
close $events;
# A real externally reaped child leaves manager bookkeeping stale until reaping.
my ($reaped, $reaped_events, $reaped_control) = worker(1);
close $reaped_control;
waitpid($reaped, 0);
@owned = ();
is_deeply [$manager->running_procs], [$reaped], 'manager still records the reaped process before reload';
@targets = ();
{
    local $SIG{__WARN__} = sub { };
    $SIG{HUP}->();
}
is_deeply \@targets, [], 'reload reaps stale ownership before selecting targets';
is_deeply [$manager->running_procs], [], 'reload removes completed-worker bookkeeping';
close $reaped_events;
for my $signal (qw(TERM INT)) {
    my ($pid, $event, $release) = worker(0);
    @targets = ();
    {
        no warnings 'redefine';
        local *Parallel::ForkManager::wait_all_children = sub { die "shutdown must not block\n" };
        eval { $SIG{$signal}->() };
    }
    is $@, "script exit\n", "$signal exits the daemon";
    is_deeply \@targets, [$pid], "$signal targets its real owned worker";
    $manager->wait_all_children;
    is_deeply [$manager->running_procs], [], "$signal worker can be harvested";
    my $byte;
    is sysread($event, $byte, 1), 1, "$signal was delivered before shutdown";
    is $byte, 'T', 'shutdown worker received TERM';
    close $release;
    close $event;
    @owned = ();
}
pipe(my $fork_read, my $fork_write) or die $!;
my $forked;
{
    no warnings 'redefine';
    local *Parallel::ForkManager::start = sub {
        $manager = $_[0];
        if ($forked) {
            close $fork_write;
            $manager->wait_all_children;
            die "fork race complete\n";
        }
        local $signal_at_fork = 1;
        my $pid = $start->(@_);
        unless ($pid) {
            $SIG{TERM} = 'DEFAULT';
            close $fork_write;
            my $byte;
            sysread($fork_read, $byte, 1);
            POSIX::_exit(0);
        }
        $forked = $pid;
        return $pid;
    };
    @targets = ();
    eval { $Daemon::Control::config->{program}->() };
    POSIX::sigprocmask(POSIX::SIG_SETMASK(), POSIX::SigSet->new);
    is $@, "fork race complete\n", 'completed signal-during-fork scenario';
}
is_deeply \@targets, [$forked], 'signal during fork reaches the newly registered child';
close $fork_read;
$manager->set_max_procs(0);
$start->($manager);
my $debug_warnings = '';
@targets = ();
{
    local $SIG{__WARN__} = sub { $debug_warnings .= $_[0] };
    $SIG{HUP}->();
}
is $debug_warnings, '', 'non-forking reload never attempts to reap itself';
is_deeply \@targets, [], 'non-forking reload never signals itself';
alarm 0;
done_testing;

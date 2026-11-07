use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use File::Temp qw(tempdir);
use Wing::Command;
use Wing::Command::Command::rest;
use Wing::Command::Command::web;

local $ENV{WING_APP} = $FindBin::Bin;
for my $class (qw(Wing::Command::Command::rest Wing::Command::Command::web)) {
    my $directory = tempdir(CLEANUP => 1);
    no strict 'refs';
    no warnings 'redefine';
    local *{"${class}::service_file"} = sub { "$directory/service.$_[1]" };

    my @restart = $class->command({restart => 1, workers => 2});
    is_deeply \@restart, [$class->command({start => 1, workers => 2})], "$class --restart starts the service when its PID file is missing";
    ok grep({ $_ eq '--daemonize' } @restart), "$class --restart without a PID file daemonizes like --start";
    my @stop = $class->command({stop => 1, restart => 1, workers => 2});
    ok !grep({ $_ eq '--daemonize' } @stop), "$class --stop wins over --restart without a PID file";

    open my $pid, '>', "$directory/service.pid" or die $!;
    print $pid "999999\n";
    close $pid;
    ok grep({ $_ eq '--restart' } $class->command({restart => 1, workers => 2})), "$class --restart restarts when its PID file exists";

    # No status file, so start_server --restart fails before signalling anything.
    my $error = do { local $@; eval { $class->execute({restart => 1, workers => 2}, []) }; $@ };
    like $error, qr/start_server failed.*lsof -nP -iTCP:500[01].*--start/s, "$class fails with instructions when start_server fails";
}
done_testing;

package Wing::Command::Command::rest;

use Wing::Perl;
use Wing::Command -command;

sub abstract { 'control rest service' }

sub usage_desc { 'Start/Stop the starman rest service for WING.' }

sub description { 'Examples:
wing rest --start
wing rest --start --workers=15
wing rest --stop
wing rest --restart

'};

sub opt_spec {
    return (
      [ 'start', 'start the service' ],
      [ 'stop', 'stop the service' ],
      [ 'restart', 'restart the service' ],
      [ 'workers=i', 'the number of processes to start, defaults to 2', { default => 2} ],
    );
}

sub service_file { my ($self, $extension) = @_; return "/data/apps/logs/wingrest.$extension" }

sub command {
    my ($self, $opt) = @_;
    my @command = (
        'start_server',
        '--pid-file', $self->service_file('pid'),
        '--status-file', $self->service_file('status'),
    );
    # start_server --restart cannot find a server without its PID file, so start one.
    if ($opt->{start} || ($opt->{restart} && !$opt->{stop} && !-e $self->service_file('pid'))) {
        push @command,
            '--port', 5000,
            '--daemonize',
            '--log-file', $self->service_file('log'),
            '--','starman',
            '--workers', $opt->{workers},
            '--preload-app', $ENV{WING_APP}.'/bin/rest.psgi' ;
        if ($< == 0 ) { # don't run as root
            push @command,
                '--user', 'nobody',
                '--group', 'nobody';
        }
    }
    elsif ($opt->{stop}) {
        push @command,
            '--stop',
        ;
    }
    elsif ($opt->{restart}) {
        push @command,
            '--restart',
        ;
    }
    return @command;
}

sub execute {
    my ($self, $opt, $args) = @_;
    system($self->command($opt)) == 0
        or die "wing rest: start_server failed; its error is above. If port 5000 is in use but there is no PID file, stop the process holding the port (lsof -nP -iTCP:5000 -sTCP:LISTEN), then run wing rest --start.\n";
}

1;

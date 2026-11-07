package Wing::Command::Command::web;

use Wing::Perl;
use Wing::Command -command;

sub abstract { 'control web service' }

sub usage_desc { 'Start/Stop the starman web service for WING.' }

sub description { 'Examples:
wing web --start
wing web --start --workers=15
wing web --stop
wing web --restart
'};

sub opt_spec {
    return (
      [ 'start', 'start the service' ],
      [ 'stop', 'stop the service' ],
      [ 'restart', 'restart the service' ],
      [ 'workers=i', 'the number of processes to start, defaults to 2', { default => 2} ],
    );
}

sub service_file { my ($self, $extension) = @_; return "/data/apps/logs/wingweb.$extension" }

sub command {
    my ($self, $opt) = @_;
    my @command = (
        'start_server',
        '--pid-file', $self->service_file('pid'),
        '--status-file', $self->service_file('status'),
    );
    # start_server --restart cannot find a server without its PID file, so start one.
    if ($opt->{start} || ($opt->{restart} && !-e $self->service_file('pid'))) {
        push @command,
            '--port', 5001,
            '--daemonize',
            '--log-file', $self->service_file('log'),
            '--','starman',
            '--workers', $opt->{workers},
            '--preload-app', $ENV{WING_APP}.'/bin/web.psgi' ;
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
        or die "start_server failed (exit status $?). Read ".$self->service_file('log').", then run wing web --stop and wing web --start.\n";
}

1;

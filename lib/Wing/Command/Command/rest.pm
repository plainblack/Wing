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

sub execute {
    my ($self, $opt, $args) = @_;
    my @command = (
        'start_server', 
        '--pid-file', '/data/apps/logs/wingrest.pid',
        '--status-file', '/data/apps/logs/wingrest.status',
            );
    if ($opt->{start}) {
        push @command,
            '--port', 5000,
            '--daemonize',
            '--log-file', '/data/apps/logs/wingrest.log',
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
    system(@command);
}

1;

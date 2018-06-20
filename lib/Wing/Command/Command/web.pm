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

sub execute {
    my ($self, $opt, $args) = @_;
    my @command = (
        'start_server', 
        '--pid-file', '/data/apps/logs/wingweb.pid',
        '--status-file', '/data/apps/logs/wingweb.status',
            );
    if ($opt->{start}) {
        push @command,
            '--port', 5001,
            '--daemonize',
            '--log-file', '/data/apps/logs/wingweb.log',
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
    system(@command);
}

1;

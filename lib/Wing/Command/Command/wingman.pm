package Wing::Command::Command::wingman;

use Wing::Perl;
use Wing::Command -command;

sub abstract { 'control wingman service' }

sub usage_desc { 'Start/Stop the wingman job service for WING.' }

sub description { 'Examples:
wing wingman --start
wing wingman --start --watchself
wing wingman --start --watch=some_tube_name
wing wingman --stop
wing wingman --restart
'};

sub opt_spec {
    return (
      [ 'start', 'start the service' ],
      [ 'stop', 'stop the service' ],
      [ 'restart', 'restart the service' ],
      [ 'watchself', 'watch a tube for its own host' ],
      [ 'watch=s', 'a list of tube to watch, comma separated with no whitespace' ],
    );
}

sub execute {
    my ($self, $opt, $args) = @_;
    my @command = (
        'wingman.pl', 
            );
    if ($opt->{start}) {
        push @command, 'start';
    }
    elsif ($opt->{stop}) {
        push @command, 'stop';
    }
    elsif ($opt->{restart}) {
        push @command, 'restart';
    }
    my @tubes_to_watch;
    if ($opt->{watchself}) {
        my $identify = q!ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p'!;
        my $host = `$identify`;
        chomp $host;
        push @tubes_to_watch, $host;
    }
    if ($opt->{watch}) {
        push @tubes_to_watch, split /,/, $opt->{watch};
    }
    if (@tubes_to_watch) {
        push @command, '--watch', join(',', @tubes_to_watch);
    }
    system(@command);
}

1;

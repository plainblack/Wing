#!/data/apps/bin/perl

use Fcntl qw(:flock);

BEGIN {
 die "Must set WING_HOME environment variable." unless $ENV{WING_HOME};
 die "Must set WING_APP environment variable." unless $ENV{WING_APP};
 die "Must set WING_CONFIG environment variable." unless $ENV{WING_CONFIG};
}

use lib $ENV{WING_APP}.'/lib', $ENV{WING_HOME}.'/lib';

if (exists $ENV{'WING_OWNER'}) {
    eval q|use lib $ENV{WING_OWNER}.'/lib';|;
}
# stop multiple copies from running
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
    print "$0 is already running. Exiting.\n";
    exit(1);
}
 
use Wing::Command;

my $app = Wing::Command->new();
warn ("Got app\n");

unshift @ARGV, qw/trends --calc/;

$app->run;

__DATA__
This exists so flock() code above works.
DO NOT REMOVE THIS DATA SECTION.

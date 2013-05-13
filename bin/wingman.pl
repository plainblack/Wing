#!/usr/bin/env perl

BEGIN {
 die "Must set WING_HOME environment variable." unless $ENV{WING_HOME};
 die "Must set WING_APP environment variable." unless $ENV{WING_APP};
}
use lib $ENV{WING_APP}.'/lib', $ENV{WING_HOME}.'/lib';

use Wingman;
use Wing::Perl;

print "Wingman Running\n";
Wingman->new->run();


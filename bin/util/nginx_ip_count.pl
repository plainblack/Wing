#!/data/apps/bin/perl

use strict;
use warnings;

# cat or tail  a log file into this program to get a count of hits by ip address 

my %ipcount;
while (my $line = <>) {
    $line =~ m/^.*\s+\"(.*)\"$/;
    $ipcount{$1}++;
}

foreach my $ip (sort { $ipcount{$a} <=> $ipcount{$b} } keys %ipcount) {
	printf "%s (%d)\n", $ip, $ipcount{$ip}; 
}


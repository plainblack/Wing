#!/usr/bin/env perl

use lib $ENV{WING_APP}.'/lib', '/data/Wing/lib';

use Wing::Perl;
use Wing;
use Getopt::Long;

GetOptions(
    'h|hour'  => \my $hour,
    'd|day'   => \my $day,
    'm|month' => \my $month,
    'y|year'  => \my $year,
    'fix'     => \my $fix,
);

my ($date, $name);

if (scalar @ARGV == 3) {
    $date = shift(@ARGV) . ' '. shift(@ARGV);
    $name = shift(@ARGV)
}
else {
    $date = shift @ARGV;
    $name = shift @ARGV
}

die "Must supply date and name\n" unless $date && $name;

my ($table_name, $date_name);

if ($hour) {
    $table_name = 'TrendsLogHourly';
    $date_name  = 'hour';
}
elsif ($day) {
    $table_name = 'TrendsLogDaily';
    $date_name  = 'day';
}
elsif ($month) {
    $table_name = 'TrendsLogMonthly';
    $date_name  = 'month';
}
elsif ($year) {
    $table_name = 'TrendsLogYearly';
    $date_name  = 'year';
}

my $rs = Wing->db->resultset($table_name);

my $entries = $rs->search({$date_name => $date, name => $name, });
my $count = $entries->count;

say "$hour $name has $count entries in table $table_name";

while (my $entry = $entries->next) {
    say join ' ', $entry->id, $entry->date_created, $entry->date_updated, $entry->value;
}

#!/usr/bin/env perl

use lib $ENV{WING_APP}.'/lib', '/data/Wing/lib';

use Wing::Perl;
use Wing;
use Getopt::Long;
use Wing::TrendsLogger qw//;

GetOptions(
    'h|hour'  => \my $hour,
    'd|day'   => \my $day,
    'm|month' => \my $month,
    'y|year'  => \my $year,
    'fix'     => \my $fix,
    'names'   => \my $names,
);

my ($date, $single_name);

if (scalar @ARGV == 3 || scalar(@ARGV) == 2 && $names) {
    $date = shift(@ARGV) . ' '. shift(@ARGV);
    $single_name = shift(@ARGV)
}
else {
    $date = shift @ARGV;
    $single_name = shift @ARGV
}

die "Must supply date and name\n" unless $date && ($single_name || $names);

my @names = $names ? Wing::TrendsLogger::trend_names() : ($single_name);

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

my $date_entries = $rs->search({$date_name => $date, },);

foreach my $name (@names) {
    my $entries = $date_entries->search({name => $name, }, {order_by => { -desc => [qw/date_created date_updated/], } });
    my $count = $entries->count;

    say "$hour $name has $count entries in table $table_name";

    my $skip_first = 1;
    while (my $entry = $entries->next) {
        say join ' ', $entry->id, $entry->date_created, $entry->date_updated, $entry->value;
        if ($fix) {
            if ($skip_first) {
                $skip_first = 0;
            }
            else {
                say "Deleting older duplicate";
                $entry->delete;
            }
        }
    }
}

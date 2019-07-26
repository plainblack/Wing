#!/usr/bin/env perl

use lib $ENV{WING_APP}.'/lib', '/data/Wing/lib';

use Wing::Perl;
use Wing;
use Wing::TrendsLogger qw//;
use Wing::Command::Command::trends;
use JSON qw//;

$| = 1;

my %hours_to_repair;
my %days_to_repair;
my %months_to_repair;
my %years_to_repair;

my $dtf = Wing->db->storage->datetime_parser;

my @names = Wing::TrendsLogger::trend_names();

say "Hours";

my $hours_rs = Wing->db->resultset('TrendsLogHourly');
my $hours    = $hours_rs->search({}, {distinct => 1,})->get_column('hour');

HOUR: while (my $hour = $hours->next) {
    say $hour;
    NAME: foreach my $name (@names) {
        my $hour_count = $hours_rs->search({hour => $hour, name => $name, })->count;
        next NAME unless $hour_count > 1;
        $hours_to_repair{$hour}->{$name}++;
        say "DUPL $hour $name";
    }
}

say "Days";

my $days_rs = Wing->db->resultset('TrendsLogDaily');
my $days    = $days_rs->search({}, {distinct => 1,})->get_column('day');

DAY: while (my $day = $days->next) {
    say $day;
    NAME: foreach my $name (@names) {
        my $day_count = $days_rs->search({day => $day, name => $name, })->count;
        next NAME unless $day_count > 1;
        $days_to_repair{$day}->{$name}++;
        say "DUPL $day $name";
    }
}

say "Months";

my $months_rs = Wing->db->resultset('TrendsLogMonthly');
my $months    = $months_rs->search({}, {distinct => 1,})->get_column('month');

MONTH: while (my $month = $months->next) {
    say $month;
    NAME: foreach my $name (@names) {
        my $month_count = $months_rs->search({month => $month, name => $name, })->count;
        next NAME unless $month_count > 1;
        $months_to_repair{$month}->{$name}++;
        say "DUPL $month $name";
    }
}

say "Years";

my $years_rs = Wing->db->resultset('TrendsLogYearly');
my $years    = $years_rs->search({}, {distinct => 1,})->get_column('year');

YEAR: while (my $year = $years->next) {
    say $year;
    NAME: foreach my $name (@names) {
        my $year_count = $years_rs->search({year => $year, name => $name, })->count;
        next NAME unless $year_count > 1;
        $years_to_repair{$year}->{$name}++;
        say "DUPL $year $name";
    }
}

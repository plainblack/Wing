package Wing::Command::Command::trends;

use Wing;
use Wing::Perl;
use Wing::Command -command;
use Ouch;
use POSIX qw(ceil);
use Wing::TrendsLogger qw(:all);

sub abstract { 'calculate trends' }

sub usage_desc { 'Calculate trends.' }

sub description {'Examples:
 wing trends --calc

 wing trends --recalc --start="2015-01-01 00:00:00" --end="2015-02-01 00:00:00"
'}

sub opt_spec {
    return (
      [ 'calc', 'calculate todays trends' ],
      [ 'recalc', 'recalculate trends in the past, must include a start and end, and may include a target' ],
      [ 'recalc_one=s', 'recalculate a specific trend passed in her, must include a start and an end' ],
      [ 'names', 'output all names, including delta_names' ],
      [ 'delta_names', 'output all delta_names' ],
      [ 'target=s', 'when performing a recalc, what should be recalculated. Choose from "all" (default), "hourly", "daily", "monthly", "yearly", or "deltas"' ],
      [ 'quiet', 'silence output' ],
      [ 'start=s', 'where to start the recalculation' ],
      [ 'end=s', 'where to end the recalculation' ],
      [ 'log=s', 'add a new trend into the calculation' ],
      [ 'value=s', 'if you add a new trend you must set a value' ],
      [ 'note=s', 'if you add a new trend you must say what caused you to log it' ],
    );
}

sub validate_args {
    my ($self, $opt, $args) = @_;
    # no args allowed but options!
    $self->usage_error("No args allowed, only options.") if @$args;
}

sub execute {
    my ($self, $opt, $args) = @_;
    my $log = Wing->log;
    my $deltas = trend_deltas();
    my @delta_names = trend_delta_names();
    my @names = trend_names();
    my $users = Wing->db->resultset('User');
    if ($opt->{log} && $opt->{value}) {
        log_trend($opt->{log}, $opt->{value}, $opt->{note});
        say $opt->{log}.' logged.' unless $opt->{quiet};
    }
    elsif ($opt->{recalc_one} && $opt->{start} && $opt->{end}) { # recalc some period of time for one specific trend name
        say "Recalculating '".$opt->{recalc_one}."' from ".$opt->{start}." to ".$opt->{end}."..." unless $opt->{quiet};
        if ($opt->{recalc_one} ~~ \@delta_names) {
            $self->usage_error("Cannot recalculate deltas via this method.");
        }
        my $target = $opt->{target} || 'all';
        my $day = Wing->from_mysql($opt->{start});
        my $stop = Wing->from_mysql($opt->{end});
        while ($day <= $stop) {
            say $day unless $opt->{quiet};
            hourly($day, [$opt->{recalc_one}], []);
            if ($day->hour == 23) {
                daily($day, [$opt->{recalc_one}], []);
                monthly($day, [$opt->{recalc_one}], []);
                yearly($day, [$opt->{recalc_one}], []);
            }
            $day->add(hours => 1);
        }
        say "Recalc complete." unless $opt->{quiet};
    }
    elsif ($opt->{recalc} && $opt->{start} && $opt->{end}) { # recalc some period of time
        say "Recalculating trends from ".$opt->{start}." to ".$opt->{end}."..." unless $opt->{quiet};
        my $target = $opt->{target} || 'all';
        my $day = Wing->from_mysql($opt->{start});
        my $stop = Wing->from_mysql($opt->{end});
        while ($day <= $stop) {
            say $day unless $opt->{quiet};
            hourly($day, \@names, \@delta_names) if $target eq 'all' || $target eq 'hourly';
            if ($day->hour == 23) {
                daily($day, \@names, \@delta_names) if $target eq 'all' || $target eq 'daily';
                monthly($day, \@names, \@delta_names) if $target eq 'all' || $target eq 'monthly';
                yearly($day, \@names, \@delta_names) if $target eq 'all' || $target eq 'yearly';
                deltas($day, $deltas, 1) if $target eq 'all' || $target eq 'deltas';
            }
            $day->add(hours => 1);
        }
        say "Recalc complete." unless $opt->{quiet};
    }
    elsif ($opt->{calc}) { # default
        say "Calculating trends..." unless $opt->{quiet};
        # make sure we've updated the remainder of the past hour
        my $day = DateTime->now->subtract(hours=>1);
        $day->set_minute(0);
        $day->set_second(0);
        hourly($day, \@names, \@delta_names);
        daily($day, \@names, \@delta_names);
        monthly($day, \@names, \@delta_names);
        yearly($day, \@names, \@delta_names);

        # now we can update the current time
        $day->add(hours=>1);
        deltas($day, $deltas);
        hourly($day, \@names, \@delta_names);
        daily($day, \@names, \@delta_names);
        monthly($day, \@names, \@delta_names);
        yearly($day, \@names, \@delta_names);
        say "Calculation complete." unless $opt->{quiet};
    }
    elsif ($opt->{names}) {
        say join "\n", @names;
    }
    elsif ($opt->{delta_names}) {
        say join "\n", @delta_names;
    }
    else {
        say "You must specify --calc, --recalc, --names, --delta_names, or --log.";
    }
}

sub deltas {
    my ($day, $deltas, $skip_hourly) = @_;
    my $db = Wing->db;
    my $dtf = Wing->db->storage->datetime_parser;
    my $end_date = $day->clone;
    $end_date->set_minute(0);
    $end_date->set_second(0);
    my $end = $dtf->format_datetime($end_date);
    my $start = $dtf->format_datetime($end_date->clone->subtract(days => 1));
    my $trends_hourly = Wing->db->resultset('TrendsLogHourly')->search({hour => {-between => [$start, $end]}});
    $end_date->set_hour(0);
    $end = $dtf->format_datetime($end_date);
    $start = $dtf->format_datetime($end_date->clone->subtract(months => 1));
    my $trends_daily = Wing->db->resultset('TrendsLogDaily')->search({day => {-between => [$start, $end]}});
    $end_date->set_day(1);
    $end = $dtf->format_datetime($end_date);
    $start = $dtf->format_datetime($end_date->clone->subtract(years => 1));
    my $trends_monthly = Wing->db->resultset('TrendsLogMonthly')->search({month => {-between => [$start, $end]}});

    foreach my $key (keys %{$deltas}) {
        log_trend_hourly($key, $deltas->{$key}->($day), $day) unless $skip_hourly;
        log_trend_daily($key, $trends_hourly->search({name => $key})->get_column('value')->func('AVG'), $day);
        log_trend_monthly($key, $trends_daily->search({name => $key})->get_column('value')->func('AVG'), $day);
        log_trend_yearly($key, $trends_monthly->search({name => $key})->get_column('value')->func('AVG'), $day);
    }
}

sub hourly {
    my ($day, $names, $delta_names) = @_;
    my $dtf = Wing->db->storage->datetime_parser;
    my $start_date = $day->clone;
    $start_date->set_minute(0);
    $start_date->set_second(0);
    my $start = $dtf->format_datetime($start_date);
    my $end = $dtf->format_datetime($start_date->clone->add(hours => 1)->subtract(seconds => 1));
    my $trends = Wing->db->resultset('TrendsLog');
    my $logs = $trends->search({date_created => {-between => [$start, $end]}});
    foreach my $name (@{$names}) {
        next if $name ~~ $delta_names;
        log_trend_hourly($name, $logs->search({name => $name})->get_column('value')->sum + 0, $day);
    }
}

sub daily {
    my ($day, $names, $delta_names) = @_;
    my $dtf = Wing->db->storage->datetime_parser;
    my $start_date = $day->clone;
    $start_date->set_hour(0);
    my $start = $dtf->format_datetime($start_date);
    my $end = $dtf->format_datetime($start_date->clone->add(days=>1)->subtract(seconds => 1));
    my $trends_hourly = Wing->db->resultset('TrendsLogHourly');
    my $logs = $trends_hourly->search({hour => {-between => [$start, $end]}});
    foreach my $name (@{$names}) {
        next if $name ~~ $delta_names;
        log_trend_daily($name, $logs->search({name => $name})->get_column('value')->sum + 0, $day);
    }
}

sub monthly {
    my ($day, $names, $delta_names) = @_;
    my $dtf = Wing->db->storage->datetime_parser;
    my $start_date = $day->clone;
    $start_date->set_day(1);
    $start_date->set_hour(0);
    my $start = $dtf->format_datetime($start_date);
    my $end = $dtf->format_datetime($start_date->clone->add(months=>1)->subtract(seconds => 1));
    my $trends_daily = Wing->db->resultset('TrendsLogDaily');
    my $logs = $trends_daily->search({day => {-between => [$start, $end]}});
    foreach my $name (@{$names}) {
        next if $name ~~ $delta_names;
        log_trend_monthly($name, $logs->search({name => $name})->get_column('value')->sum + 0, $day);
    }
}

sub yearly {
    my ($day, $names, $delta_names) = @_;
    my $dtf = Wing->db->storage->datetime_parser;
    my $start_date = $day->clone;
    $start_date->set_month(1);
    $start_date->set_day(1);
    $start_date->set_hour(0);
    my $start = $dtf->format_datetime($start_date);
    my $end = $dtf->format_datetime($start_date->clone->add(years=>1)->subtract(seconds => 1));
    my $trends_monthly = Wing->db->resultset('TrendsLogMonthly');
    my $logs = $trends_monthly->search({month => {-between => [$start, $end]}});
    foreach my $name (@{$names}) {
        next if $name ~~ $delta_names;
        log_trend_yearly($name, $logs->search({name => $name})->get_column('value')->sum + 0, $day);
    }
}

1;

=head1 NAME

wing trends - Calculate trends.

=head1 SYNOPSIS

 wing trends --log=ping --value=1 --note="Just Because"

 wing trends --calc

 wing trends --recalc --start="2015-01-01 00:00:00" --end="2015-02-01 00:00:00"

=head1 DESCRIPTION

This provides calculation of long-term trends. It should be run regularly (at least hourly) via a cron job. The resulting data is viewable through trends reports in the admin web interface.

=head1 AUTHOR

Copyright 2015 Plain Black Corporation.

=cut

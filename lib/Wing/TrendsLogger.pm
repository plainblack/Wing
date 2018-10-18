package Wing::TrendsLogger;

use Wing::Perl;
use Wing;
use Ouch;
use parent 'Exporter';
our @EXPORT_OK = qw(log_trend log_trend_hourly log_trend_daily log_trend_monthly log_trend_yearly log_trend_all trend_names trend_deltas trend_delta_names);
our %EXPORT_TAGS = ( all => [qw(log_trend log_trend_hourly log_trend_daily log_trend_monthly log_trend_yearly log_trend_all trend_names trend_deltas trend_delta_names)]);

sub trend_names {
    my @names = Wing->db->resultset('TrendsLog')->search(undef, { distinct => 1})->get_column('name')->all;
    foreach my $name (trend_delta_names()) {
        push @names, $name;
    }
    return @names;
}

sub trend_delta_names {
    return keys %{trend_deltas()};
}

sub trend_deltas {
    return Wing->db->resultset('TrendsLog')->new({})->trend_deltas;
}

sub log_trend {
    my ($name, $value, $note, $date) = @_;
    return unless defined $value;
    $date ||= DateTime->now;
    Wing->db->resultset('TrendsLog')->new({name => $name, value => $value, note => $note, date_created => $date, date_updated => $date})->insert;
}

sub log_trend_hourly {
    my ($name, $value, $hour) = @_;
    return unless defined $value;
    my $dtf = Wing->db->storage->datetime_parser;
    my $trends_hourly = Wing->db->resultset('TrendsLogHourly');
    my $row = $trends_hourly->search({hour => $dtf->format_datetime($hour), name => $name},{rows=>1})->single;
    if (defined $row) {
        Wing->log->info("Updating $name record for hour $hour with value $value");
        $row->update({name => $name, value => $value, hour => $hour});
    }
    else {
        Wing->log->info("Creating $name record for hour $hour with value $value");
        $row = $trends_hourly->new({name => $name, value => $value, hour => $hour})->insert;
    }
}

sub log_trend_daily {
    my ($name, $value, $date) = @_;
    return unless defined $value;
    my $dtf = Wing->db->storage->datetime_parser;
    my $day = $date->clone;
    $day->set_hour(0);
    my $trends_daily = Wing->db->resultset('TrendsLogDaily');
    my $row = $trends_daily->search({day => $dtf->format_datetime($day), name => $name},{rows=>1})->single;
    if (defined $row) {
        Wing->log->info("Updating $name record for day $day with value $value");
        $row->update({name => $name, value => $value, day => $day});
    }
    else {
        Wing->log->info("Creating $name record for day $day with value $value");
        $row = $trends_daily->new({name => $name, value => $value, day => $day})->insert;
    }
}

sub log_trend_monthly {
    my ($name, $value, $date) = @_;
    return unless defined $value;
    my $dtf = Wing->db->storage->datetime_parser;
    my $month = $date->clone;
    $month->set_hour(0);
    $month->set_day(1);
    my $trends_monthly = Wing->db->resultset('TrendsLogMonthly');
    my $row = $trends_monthly->search({month => $dtf->format_datetime($month), name => $name},{rows=>1})->single;
    if (defined $row) {
        Wing->log->info("Updating $name record for month $month with value $value");
        $row->update({name => $name, value => $value, month => $month});
    }
    else {
        Wing->log->info("Creating $name record for month $month with value $value");
        $row = $trends_monthly->new({name => $name, value => $value, month => $month})->insert;
    }
}

sub log_trend_yearly {
    my ($name, $value, $date) = @_;
    return unless defined $value;
    my $dtf = Wing->db->storage->datetime_parser;
    my $year = $date->clone;
    $year->set_hour(0);
    $year->set_day(1);
    $year->set_month(1);
    my $trends_yearly = Wing->db->resultset('TrendsLogYearly');
    my $row = $trends_yearly->search({year => $dtf->format_datetime($year), name => $name},{rows=>1})->single;
    if (defined $row) {
        Wing->log->info("Updating $name record for year $year with value $value");
        $row->update({name => $name, value => $value, year => $year});
    }
    else {
        Wing->log->info("Creating $name record for year $year with value $value");
        $row = $trends_yearly->new({name => $name, value => $value, year => $year})->insert;
    }
}

sub log_trend_all {
    my ($name, $value, $day) = @_;
    return unless defined $value;
    log_trend_hourly($name, $value, $day);
    log_trend_daily($name, $value, $day);
    log_trend_monthly($name, $value, $day);
    log_trend_yearly($name, $value, $day);
}

1;

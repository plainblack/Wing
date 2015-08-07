package Wing::Rest::Trends;

use Wing::Perl;
use Wing;
use Dancer;
use Wing::Rest;
use Ouch;
use DateTime;
use Wing::TrendsLogger;

sub quote_array {
    my @trends = @_;
    my $dbh = Wing->db->storage->dbh;
    my @names = ();
    foreach my $trend (@trends) {
        push @names, $dbh->quote($trend);
    }
    return @names;
}

sub parse_start_date {
    my ($date_string) = @_;
    if (defined $date_string) {
        return Wing->from_mysql($date_string.' 23:59:59');
    }
    else {
        return DateTime->now;
    }
}

get '/api/trends/hourly/:id' => sub {
    my $user = get_user_by_session_id()->verify_is_admin();
    my $report = fetch_object('TrendsReport');
    my %labels;
    my @trends;
    foreach my $trend (@{$report->fields}) {
        $labels{$trend->{name}} = $trend->{label};
        push @trends, $trend->{name};
    }
    my $dtf = Wing->db->storage->datetime_parser;
    my $now = parse_start_date(params->{start});
    $now->set_minute(0);
    $now->set_second(0);
    my $then = $now->clone->subtract(hours => 24);
    my $sth = Wing->db->storage->dbh->prepare("select cast(substring(hour,12,2) as UNSIGNED),name,value from trends_logs_hourly where name in (".join(',',quote_array(@trends)).") and hour between ? and ? order by hour desc");
    $sth->execute($dtf->format_datetime($then), $dtf->format_datetime($now));    
    my %raw;
    while (my ($hour, $name, $value) = $sth->fetchrow_array) {
        $raw{$hour}{$name} = $value;
    }
    my @rows;
    foreach my $name (@trends) {
        my $today = $now->clone;
        my @row = ($labels{$name});
        my $total = 0;
        my $count = 0;
        while ($today > $then) {
            my $value = $raw{$today->hour}{$name} + 0;
            push @row, $value;
            $total += $value;
            $count++;
            $today->subtract(hours=>1);
        }
        push @row, $total, sprintf('%.2f', $total/$count);
        push @rows, \@row;
    }
    my @head = ('Trend');
    while ($now > $then) {
        push @head, $now->hour;
        $now->subtract(hours=>1);
    }
    push @head, 'Total', 'Average';
    return {
        name        => $report->name,
        headings    => \@head,
        rows        => \@rows,
    }
};


get '/api/trends/daily/:id' => sub {
    my $user = get_user_by_session_id()->verify_is_admin();
    my $report = fetch_object('TrendsReport');
    my %labels;
    my @trends;
    foreach my $trend (@{$report->fields}) {
        $labels{$trend->{name}} = $trend->{label};
        push @trends, $trend->{name};
    }
    my $dtf = Wing->db->storage->datetime_parser;
    my $now = parse_start_date(params->{start});
    $now->set_hour(0);
    $now->set_minute(0);
    $now->set_second(0);
    my $then = $now->clone->subtract(days => params->{range});
    my $sth = Wing->db->storage->dbh->prepare("select substring(day,1,10),name,value from trends_logs_daily where name in (".join(',',quote_array(@trends)).") and day between ? and ? order by day desc");
    $sth->execute($dtf->format_datetime($then), $dtf->format_datetime($now));    
    my %raw;
    while (my ($day, $name, $value) = $sth->fetchrow_array) {
        $raw{$day}{$name} = $value;
    }
    my @rows;
    foreach my $name (@trends) {
        my $today = $now->clone;
        my @row = ($labels{$name});
        my $total = 0;
        my $count = 0;
        while ($today > $then) {
            my $value = $raw{$today->ymd}{$name} + 0;
            push @row, $value;
            $total += $value;
            $count++;
            $today->subtract(days=>1);
        }
        push @row, $total, sprintf('%.2f', $total/$count);
        push @rows, \@row;
    }
    my @head = ('Trend');
    while ($now > $then) {
        push @head, $now->month .'/'. $now->day;
        $now->subtract(days=>1);
    }
    push @head, 'Total', 'Average';
    return {
        name        => $report->name,
        headings    => \@head,
        rows        => \@rows,
    }
};


get '/api/trends/monthly/:id' => sub {
    my $user = get_user_by_session_id()->verify_is_admin();
    my $report = fetch_object('TrendsReport');
    my %labels;
    my @trends;
    foreach my $trend (@{$report->fields}) {
        $labels{$trend->{name}} = $trend->{label};
        push @trends, $trend->{name};
    }
    my $dtf = Wing->db->storage->datetime_parser;
    my $now = parse_start_date(params->{start});
    $now->set_day(1);
    $now->set_hour(0);
    $now->set_minute(0);
    $now->set_second(0);
    my $then = $now->clone->subtract(months => params->{range});
    my $sth = Wing->db->storage->dbh->prepare("select substring(month,1,10),name,value from trends_logs_monthly where name in (".join(',',quote_array(@trends)).") and month between ? and ? order by month desc");
    $sth->execute($dtf->format_datetime($then), $dtf->format_datetime($now));    
    my %raw;
    while (my ($day, $name, $value) = $sth->fetchrow_array) {
        $raw{$day}{$name} = $value;
    }
    my @rows;
    foreach my $name (@trends) {
        my $today = $now->clone;
        my @row = ($labels{$name});
        my $total = 0;
        my $count = 0;
        while ($today > $then) {
            my $value = $raw{$today->ymd}{$name} ? $raw{$today->ymd}{$name} : 0;
            push @row, $value;
            $total += $value;
            $count++;
            $today->subtract(months=>1);
        }
        push @row, $total, sprintf('%.2f', $total/$count);
        push @rows, \@row;
    }
    my @head = ('Trend');
    while ($now > $then) {
        push @head, $now->month .'/'. $now->year;
        $now->subtract(months=>1);
    }
    push @head, 'Total', 'Average';
    return {
        name        => $report->name,
        headings    => \@head,
        rows        => \@rows,
    }
};


get '/api/trends/yearly/:id' => sub {
    my $user = get_user_by_session_id()->verify_is_admin();
    my $report = fetch_object('TrendsReport');
    my %labels;
    my @trends;
    foreach my $trend (@{$report->fields}) {
        $labels{$trend->{name}} = $trend->{label};
        push @trends, $trend->{name};
    }
    my $dtf = Wing->db->storage->datetime_parser;
    my $now = parse_start_date(params->{start});
    $now->set_day(1);
    $now->set_month(1);
    my $then = $now->clone->subtract(years => params->{range});
    my $sth = Wing->db->storage->dbh->prepare("select substring(year,1,10),name,value from trends_logs_yearly where name in (".join(',',quote_array(@trends)).") and year between ? and ? order by year desc");
    $sth->execute($dtf->format_datetime($then), $dtf->format_datetime($now));    
    my %raw;
    while (my ($day, $name, $value) = $sth->fetchrow_array) {
        $raw{$day}{$name} = $value;
    }
    my @rows;
    foreach my $name (@trends) {
        my $today = $now->clone;
        my @row = ($labels{$name});
        my $total = 0;
        my $count = 0;
        while ($today > $then) {
            my $value = $raw{$today->ymd}{$name} + 0;
            push @row, $value;
            $total += $value;
            $count++;
            $today->subtract(years=>1);
        }
        push @row, $total, sprintf('%.2f', $total/$count);
        push @rows, \@row;
    }
    my @head = ('Trend');
    while ($now > $then) {
        push @head, $now->year;
        $now->subtract(years=>1);
    }
    push @head, 'Total', 'Average';
    return {
        name        => $report->name,
        headings    => \@head,
        rows        => \@rows,
    }
};

get '/api/trendsreport' => sub {
    my $user = get_user_by_session_id()->verify_is_admin();
    my $data = site_db()->resultset('TrendsReport')->search(undef,{order_by => 'name'});
    return format_list($data, current_user => $user); 
};

get '/api/trendsnames' => sub {
    return {
        names => [Wing::TrendsLogger::trend_names()]
    };
};

generate_crud('TrendsReport');
generate_all_relationships('TrendsReport');

1;

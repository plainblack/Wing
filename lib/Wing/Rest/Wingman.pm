package Wing::Rest::Wingman;

use Wing::Perl;
use Ouch;
use Wing::Session;
use Dancer;
use Wing::Rest;
use Wingman;

get '/api/wingman/stats' => sub {
    my $user = get_user_by_session_id()->verify_is_admin();
    return Wingman->new->stats_as_hashref;
};

### TUBES

get '/api/wingman/tubes' => sub {
    my $user = get_user_by_session_id()->verify_is_admin();
    my $wingman = Wingman->new;
    my @tubes = ();
    foreach my $tube ($wingman->list_tubes) {
        push @tubes, $wingman->stats_tube_as_hashref($tube);
    }    
    return {
        items => \@tubes,
        paging => { # simulating paging 
            total_items             => scalar @tubes,
            total_pages             => 1,
            page_number             => 1,
            items_per_page          => 1,
            next_page_number        => 1,
            previous_page_number    => 1,
        },  
    };
};
 
get '/api/wingman/tubes/:tube/stats' => sub {
    my $user = get_user_by_session_id()->verify_is_admin();
    return Wingman->new->stats_tube_as_hashref(params->{tube});
};

get '/api/wingman/tubes/:tube/jobs' => sub {
    my $user = get_user_by_session_id()->verify_is_admin();
    my $tube_name = params->{tube};
    my $wingman = Wingman->new;
    my $min = $wingman->guess_min_peek_range({ tubes => [$tube_name]});
    my $max = $wingman->guess_max_peek_range($min);
    my @jobs;
    foreach my $job_id ($min..$max) {
        my $stats = eval { $wingman->stats_job_as_hashref($job_id) };
        if (defined $stats) {
            next unless $stats->{tube} eq $tube_name;
            push @jobs, $stats;
        }
    }
    return {
        items => \@jobs,
        paging => { # simulating paging 
            total_items             => scalar @jobs,
            total_pages             => 1,
            page_number             => 1,
            items_per_page          => 1,
            next_page_number        => 1,
            previous_page_number    => 1,
        },  
    };
};

post '/api/wingman/tubes/:tube/pause' => sub {
    my $user = get_user_by_session_id()->verify_is_admin();
    my $wingman = Wingman->new;
    if ($wingman->pause_tube(params->{tube}, params->{seconds} + 0)) {
        return { success => 1 };
    }
    else {
        ouch 500, $wingman->error;
    }
};

### JOBS

get '/api/wingman/jobs' => sub {
    my $user = get_user_by_session_id()->verify_is_admin();
    my $wingman = Wingman->new;
    my $min = $wingman->guess_min_peek_range();
    my $max = $wingman->guess_max_peek_range($min);
    my @jobs;
    foreach my $job_id ($min..$max) {
        my $stats = eval { $wingman->peek($job_id)->describe };
        if (defined $stats) {
            push @jobs, $stats;
        }
    }
    return {
        items => \@jobs,
        paging => { # simulating paging 
            total_items             => scalar @jobs,
            total_pages             => 1,
            page_number             => 1,
            items_per_page          => 1,
            next_page_number        => 1,
            previous_page_number    => 1,
        },  
    };
};

get '/api/wingman/jobs/buried' => sub {
    my $user = get_user_by_session_id()->verify_is_admin();
    return Wingman->new->peek_buried->describe;
};

get '/api/wingman/jobs/ready' => sub {
    my $user = get_user_by_session_id()->verify_is_admin();
    return Wingman->new->peek_ready->describe;
};

get '/api/wingman/jobs/delayed' => sub {
    my $user = get_user_by_session_id()->verify_is_admin();
    return Wingman->new->peek_delayed->describe;
};


get '/api/wingman/jobs/:id' => sub {
    my $user = get_user_by_session_id()->verify_is_admin();
    return Wingman->new->peek(params->{id})->describe;
};

post '/api/wingman/jobs/:id/kick' => sub {
    my $user = get_user_by_session_id()->verify_is_admin();
    my $wingman = Wingman->new;
    if ($wingman->kick_job(params->{id})) {
        return $wingman->peek(params->{id})->describe;
    }
    else {
        ouch 504, $wingman->error;
    }
};

del '/api/wingman/jobs/:id' => sub {
    my $user = get_user_by_session_id()->verify_is_admin();
    my $wingman = Wingman->new;
    if ($wingman->delete(params->{id})) {
        return { success => 1 };
    }
    else {
        ouch 504, $wingman->error;
    }
};

post '/api/wingman/jobs' => sub {
    my $user = get_user_by_session_id()->verify_is_admin();
    my $args = from_json(params->{arguments}) if params->{arguments};
    my %options = ();
    foreach my $option (qw(priority delay ttr tube)) {
        $options{$option} = params->{$option} if params->{$option};
    }
    my $job = Wingman->new->put(params->{phase}, $args, \%options);
    return $job->describe;
};


1;

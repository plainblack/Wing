package Wing::Web::Admin::Wingman;

use Dancer ':syntax';
use Wing::Perl;
use Ouch;
use Wing;
use Wing::Web;
use Wingman;

get '/admin/wingman' => sub {
    my $wingman = Wingman->new;
    template 'admin/wingman', { stats => $wingman->stats_as_hashref };
};

get '/admin/wingman/tubes/:tube' => sub {
    my $tube_name = params->{tube};
    my $wingman = Wingman->new;
    template 'admin/wingman_tube', {
        stats           => $wingman->stats_tube_as_hashref($tube_name),
        tube_name       => $tube_name,
        config          => Wing->config->get('wingman'),
    };
};

get '/admin/wingman/jobs/:job_id' => sub {
    my $tube_name = params->{tube};
    my $job_id = params->{job_id};
    my $wingman = Wingman->new;
    template 'admin/wingman_job', {
        job_id          => $job_id,
        config          => Wing->config->get('wingman'),
        stats           => $wingman->stats_job_as_hashref($job_id),
    };
};


true;

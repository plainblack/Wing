package Wingman;


=head1 NAME

Wingman - A jobs server for Wing.

=head1 SYNOPSIS

 my $wingman = Wingman->new;

 # as a client
 my $job = $wingman->add_job($plugin_name, \%args, \%opts); # create a job
 my $job = $wingman->next_job($timeout);                    # fetch a job

 # as the jobs task master
 $wingman->run;

=head1 DESCRIPTION

When you're building web services or web sites you often need to do long running tasks as background processes to avoid connection timeouts, such as sending a bunch of emails or thumbnailing images. Wingman solves this problem. Wingman also forks multiple workers so that you can run jobs in parallel taking advantage of multi-core systems; You can even run multiple wingman server instances if one server isn't cutting it.

=cut

use Wing;
use Wing::Perl;
use Wingman::Job;
use Moose;
use Plugin::Tiny;
use Beanstalk::Client;
use Parallel::ForkManager;
use JSON::XS;
use Ouch;
with 'Wingman::Role::Logger';

has plugins => (
    is      => 'ro',
    lazy    => 1,
    default => sub { 
        my $plugins = Plugin::Tiny->new;
        $plugins->register_bundle(Wing->config->get('wingman/plugins'));
        return $plugins;
    },
);

has beanstalk => (
    is      => 'ro',
    lazy    => 1,
    default => sub { 
        my $beanstalk = Beanstalk::Client->new(Wing->config->get('wingman/beanstalkd'));
        $beanstalk->encoder(sub { encode_json(\@_) });    
        $beanstalk->decoder(sub { @{decode_json(shift)} });
        return $beanstalk;
    },
    isa     => 'Beanstalk::Client',
    handles => [qw(use delete release bury touch watch watch_only peek peek_ready disconnect peek_delayed peek_buried kick kick_job stats_job stats_tube stats list_tubes list_tube_used list_tubes_watched pause_tube)],
);

has pfm => (
    is      => 'ro',
    lazy    => 1,
    default => sub { Parallel::ForkManager->new(Wing->config->get('wingman/max_workers')) },
);

has job_types => (
    is      => 'ro',
    isa     => 'ArrayRef',
    lazy    => 1,
    default => sub { 
        my @types = ();
        foreach my $plugin (values %{Wing->config->get('wingman/plugins')}) {
            push @types, $plugin->{phase};
        }
        return \@types;
    },
);

sub _instantiate_job {
    my ($self, $beanstalk_job) = @_;
    my ($plugin_name, $args) = $beanstalk_job->args;
    $self->log_info($beanstalk_job, 'Instantiating job');
    my $plugin = $self->plugins->get_plugin($plugin_name);
    if (defined $plugin) {
        return Wingman::Job->new(
            beanstalk_job   => $beanstalk_job, 
            wingman_plugin  => $plugin,
            job_args        => $args,
        );
    }
    else {
        $self->log_error($beanstalk_job, 'Plugin not found.');
        $beanstalk_job->bury;
        return ouch 440, 'Wingman plugin not found.', $plugin_name;
    }
}

sub add_job {
    my ($self, $job_type, $args, $options) = @_;
    $args = {} unless defined $args; # must be a hashref
    $options = {} unless defined $options; # must be a hashref
    if ($job_type ~~ $self->job_types) {
        return $self->_instantiate_job($self->beanstalk->put($options, $job_type, $args));
    }
    else {
        ouch 442, $job_type.' is not a defined Wingman job type.', $job_type;
    }
}

sub next_job {
    my ($self, $timeout) = @_;
    return $self->_instantiate_job($self->beanstalk->reserve($timeout));
}

sub run {
    my $self = shift;
    while (1) {
        my $pid = $self->pfm->start and next;
        $self->next_job->run;
        $self->pfm->finish;
    }
}


1;

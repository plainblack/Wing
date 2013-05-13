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

=head1 METHODS

=head2 new

Constructor.

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

=head2 Pass Through Methods

The following is a list of methods that are direct pass-through's to L<Beanstalk::Client>.

=over

=item use

=item delete

=item release

=item bury

=item touch

=item watch

=item watch_only

=item peek

=item peek_ready

=item disconnect

=item peek_delayed

=item peek_buried

=item kick

=item kick_job

=item stats_job

=item stats_tube

=item stats

=item list tubes

=item list_tube_used

=item list_tubes_watched

=item pause_tube

=back

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

=head2 add_job

Add a new job to the queue.

=over

=item phase

A string matching the the C<phase> in the config file.

=item args

A hash reference that will be passed directly to the job's C<run> method.

=item options

A hash reference of queuing options. See the C<put> method in C<Beanstalk::Client>.

=back

=cut

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

=head2 next_job 

Returns the next job on the queue. Blocks until a job is available.

=over

=item timeout

The maximum number of seconds to wait for a job to become available. Defaults to infinity. 

=back

=cut

sub next_job {
    my ($self, $timeout) = @_;
    return $self->_instantiate_job($self->beanstalk->reserve($timeout));
}

=head2 run

Starts the Wingman task master. This will fork off child processes and start executing jobs as fast as the hardware will allow. 

=cut

sub run {
    my $self = shift;
    while (1) {
        my $pid = $self->pfm->start and next;
        $self->next_job->run;
        $self->pfm->finish;
    }
}

=head1 Plugin Development

Developing Wingman plugins is simple. You just need a package that uses the C<Wingman::Role::Plugin> role, and that has a C<run> method. See the following example.

 package MyApp::Wingman::MyCustomPlugin;

 use Wing::Perl;
 use Moose;
 with 'Wingman::Role::Plugin';

 sub run {
        my ($self, $args_hashref) = @_;
         # ... your code here ...
 }

 1;

Once you've created your plugin, you need to add it to your wing config file.

 "wingman" : {
     ...,
     "plugins" : {
         "MyApp::Wingman::MyCustomPlugin" : {
             "phase" : "do_the_big_thing",
             "foo" : "bar",
         }
         ...,
     }
 }

The C<phase> is what your plugin will be known as in the system. You can also include other parameters as with the C<foo> parameter above. Other parameters will be passed to your plugin's constructor at instantiation time. This can be useful for passing in connection, encoding, path, and other properties.

Once you're set up with your new plugin, you can use it in your Wing app like this:

 Wingman->new->add_job('do_the_big_thing', \%args);

=cut

1;

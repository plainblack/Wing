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


=head1 FLOW

 +-[ Wingman Task Master ]-------+
 | +---------------------------+ |
 | | Are there enough workers? | |
 | +---------------------------+ |
 |            |                  |    +-[ Wingman Worker ]----------------------------------------------+
 |            No                 |    | +-----------------+      +-----------------------------+        |
 |            |          +----------->| | Is there a job? |-Yes->| Do we have a plugin for it? |        |
 |            v          |       |    | +-----------------+      +-----------------------------+        |
 | +------------------+  |       |    |   ^  |                     |     |                              |
 | | Spawn new woker. |--+       |    |   |  No                    No   Yes                             |
 | +------------------+          |    |   |  |                     |     |                              |
 +-------------------------------+    |   |<-+            +--------+     v                              |
                                      |   |               |            +------------------+             |
 +-[ Beanstalkd ]----------------+    |   |               v            | Load the plugin. |             |
 |                               |<-------+    +---------------+       +------------------+             |
 | Jobs are queued here.         |<------------| Bury the job. |<-+         |                           |
 |                               |<-------+    +---------------+  |         v                           |
 +-------------------------------+    |   |                   ^   |    +--------------+                 |
       ^                ^             |   |       +--------+  |   +-No-| Did it load? |                 |
       |                |             |   |       | exit() |  |        +--------------+                 |
 +-----------+          |             |   |       +--------+  |             |                           |
 | add_job() |          |             |   |             ^     |            Yes                          |
 +-----------+          |             | +------------+  |     |             |                           |
                        |             | | Delete the |  |     |             v                           |
                        |             | | job.       |  |     |       +-----------------------------+   |
                        |             | +------------+  |     |       | Run the job.                |   |
                        |             |           ^     |     |       |                             |   |
                        |             |           |     |     |       | +-------------------------+ |   |
                        |             |           +-----+     |       | | Are we taking too long? | |   |
                        |             |              |        |       | +-------------------------+ |   |
                        |             |             Yes      No       |    |                        |   |
                        |             |              |        |       |   Yes                       |   |
                        |             | +-----------------------+     |    |                        |   |
                        |             | | Did the job complete  |<----|    |                        |   |
                        |             | | successfully?         |     |    v                        |   |
                        |             | +-----------------------+     | +--------------------+      |   |
                        +-----------------------------------------------| Request more time. |      |   |
                                      |                               | +--------------------+      |   |
                                      |                               +-----------------------------+   |
                                      +-----------------------------------------------------------------+

The Wingman task master's job is simply to keep enough workers running as defined by C<max_workers> in the config file.

Workers block on their connection to beanstalkd until they receive a job. They either complete the job or fail, either way they exit so a new worker is spawned. The workers die to ensure no memory leaks or other wierdness from plugin interactions. This is less efficient than keeping them around, but the benefits outweigh the expense.

Workers have until C<TTR> (Time To Run) to complete the job. They should be wary of this and request more time from beanstalkd if they need more time. They can do this by calling the C<touch> method on the job, which will reset the TTR to it's original value. Nothing will kill them at the end of TTR, however, beanstalkd will give out the job to a new worker at the end of TTR.

If there's a chance that a plugin could hang, then the plugin needs to deal with this. L<Spawn::Safe> is a good way to deal with it.

Also, plugins should be designed to expect failure. So if there is a portion of a job that should not be run more than once, that should be tracked externally in case the plugin fails partway through, or it loses communication with beanstalkd to tell it that the job completed.

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
    handles => [qw(error use delete release bury touch watch watch_only peek peek_ready disconnect peek_delayed peek_buried kick kick_job stats_job stats_tube stats list_tubes list_tube_used list_tubes_watched pause_tube)],
);

=head2 Pass Through Methods

The following is a list of methods that are direct pass-through's to L<Beanstalk::Client>.

=over

=item error

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

=cut

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
        my $beanstalk_job = $self->beanstalk->put($options, $job_type, $args);
        $self->log_info($beanstalk_job, 'Created job');
        return $self->_instantiate_job($beanstalk_job);
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
    my $beanstalk_job = $self->beanstalk->reserve($timeout);
    $self->log_info($beanstalk_job, 'Fetched job');
    return $self->_instantiate_job($beanstalk_job);
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

=head1 SEE ALSO

See the B<Plugin Development> section of L<Wingman::Role::Plugin> for details on how to give Wingman functionality.

=cut

1;

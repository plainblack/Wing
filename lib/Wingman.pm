package Wingman;


=head1 NAME

Wingman - A jobs server for Wing.

=head1 SYNOPSIS

 my $wingman = Wingman->new;

 # as a client
 my $job = $wingman->put($plugin_name, \%args, \%opts); # create a job
 my $job = $wingman->reserve($timeout);                    # fetch a job

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
     ^                  ^             |   |       +--------+  |   +-No-| Did it load? |                 |
     |                  |             |   |       | exit() |  |        +--------------+                 |
 +-------+              |             |   |       +--------+  |             |                           |
 | put() |              |             |   |             ^     |            Yes                          |
 +-------+              |             | +------------+  |     |             |                           |
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
use JSON::XS;
use Ouch;
use List::Util qw(min max);
use POSIX qw(ceil);
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
    handles => [qw(error use delete release bury touch watch watch_only disconnect kick kick_job stats_job stats_tube stats list_tubes list_tube_used list_tubes_watched pause_tube)],
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

=item disconnect

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
    unless (defined $beanstalk_job) {
        ouch 440, 'Job not found.';
    }
    my ($plugin_name, $args) = $beanstalk_job->args;
    $self->log_info($beanstalk_job, 'Instantiating job');
    my $plugin = eval {$self->plugins->get_plugin($plugin_name)};
    if (defined $plugin) {
        return Wingman::Job->new(
            beanstalk_job   => $beanstalk_job, 
            wingman_plugin  => $plugin,
            job_args        => $args,
        );
    }
    elsif ($@) {
        $self->log_error($beanstalk_job, 'Could not load plugin, because: '.$@);
        $beanstalk_job->bury;
        return ouch 500, 'Could not load plugin.', $plugin_name;
    }
    else {
        $self->log_error($beanstalk_job, 'Plugin not found.');
        $beanstalk_job->bury;
        return ouch 440, 'Wingman plugin not found.', $plugin_name;
    }
}

=head2 put ( phase, [ args, options ] )

Add a new job to the queue.

=over

=item phase

A string matching the the C<phase> in the config file.

=item args

A hash reference that will be passed directly to the job's C<run> method.

=item options

A hash reference of queuing options.

=over

=item tube

The name of the tube you want to insert this job into. If not specified, it will be inserted into the tube specified as C<default_tube> in the config file.

=item priority

Priority to use to queue the job. Jobs with smaller priority values will be scheduled before jobs with larger priorities. The most urgent priority is 0. Defaults to the C<priority> set in the config file.

=item delay

An integer number of seconds to wait before putting the job in the ready queue. The job will be in the "delayed" state during this time. Defaults to the C<delay> set in the config file.

=item ttr

The "Time To Run". An integer number of seconds to allow a worker to run this job. This time is counted from the moment a worker reserves this job. If the worker does not delete, release, or bury the job within ttr seconds, the job will time out and the server will release the job. The minimum ttr is 1. If the client sends 0, the server will silently increase the ttr to 1. Defaults to the C<ttr> set in the config file.

=back

=back

=cut

sub put {
    my ($self, $job_type, $args, $options) = @_;
    $args = {} unless defined $args; # must be a hashref
    $options = {} unless defined $options; # must be a hashref
    my $default_tube = Wing->config->get('wingman/beanstalkd/default_tube');
    if ($job_type ~~ $self->job_types) {
        if (exists $options->{tube} && defined $options->{tube} && $options->{tube} ne $default_tube) {
            $self->use($options->{tube});
        }
        my $beanstalk_job = $self->beanstalk->put($options, $job_type, $args);
        if (exists $options->{tube} && defined $options->{tube} && $options->{tube} ne $default_tube) {
            $self->use($default_tube);
        }
        $self->log_info($beanstalk_job, 'Created job');
        return $self->_instantiate_job($beanstalk_job);
    }
    else {
        ouch 442, $job_type.' is not a defined Wingman job type.', $job_type;
    }
}

=head2 reserve ( [ timeout ] )

Returns the next job on the queue. Blocks until a job is available.

=over

=item timeout

The maximum number of seconds to wait for a job to become available. Defaults to infinity. 

=back

=cut

sub reserve {
    my ($self, $timeout) = @_;
    my $beanstalk_job = $self->beanstalk->reserve($timeout);
    $self->log_info($beanstalk_job, 'Fetched a job.');
    return $self->_instantiate_job($beanstalk_job);
}

=head2 peek ( id )

Fetch a specific job without reserving it.

=over

=item id

The unique id of the job.

=back

=cut

sub peek {
    my ($self, $id) = @_;
    my $beanstalk_job = $self->beanstalk->peek($id);
    if (defined $beanstalk_job) {
        return $self->_instantiate_job($beanstalk_job);
    }
    return undef;
}

=head2 peek_ready ( [ tube ] )

Fetch the next ready job without reserving it.

=over

=item tube

What tube to peek into. Defaults to default tube.

=back

=cut

sub peek_ready {
    my ($self, $tube) = @_;
    my $default_tube = Wing->config->get('wingman/beanstalkd/default_tube');
    if (defined $tube && $tube ne $default_tube) {
        $self->use($tube);
    }
    my $beanstalk_job = $self->beanstalk->peek_ready;
    if (defined $tube && $tube ne $default_tube) {
        $self->use($default_tube);
    }
    if (defined $beanstalk_job) {
        return $self->_instantiate_job($beanstalk_job);
    }
    return undef;
}

=head2 peek_delayed ( [ tube ] )

Fetch the next delayed job without reserving it.

=over

=item tube

What tube to peek into. Defaults to default tube.

=back

=cut

sub peek_delayed {
    my ($self, $tube) = @_;
    my $default_tube = Wing->config->get('wingman/beanstalkd/default_tube');
    if (defined $tube && $tube ne $default_tube) {
        $self->use($tube);
    }
    my $beanstalk_job = $self->beanstalk->peek_delayed;
    if (defined $tube && $tube ne $default_tube) {
        $self->use($default_tube);
    }
    if (defined $beanstalk_job) {
        return $self->_instantiate_job($beanstalk_job);
    }
    return undef;
}

=head2 peek_buried ( [ tube ] )

Fetch the next buried job without reserving it.

=over

=item tube

What tube to peek into. Defaults to default tube.

=back

=cut

sub peek_buried {
    my ($self, $tube) = @_;
    my $default_tube = Wing->config->get('wingman/beanstalkd/default_tube');
    if (defined $tube && $tube ne $default_tube) {
        $self->use($tube);
    }
    my $beanstalk_job = $self->beanstalk->peek_buried;
    if (defined $tube && $tube ne $default_tube) {
        $self->use($default_tube);
    }
    if (defined $beanstalk_job) {
        return $self->_instantiate_job($beanstalk_job);
    }
    return undef;
}


=head2 stats_tube_as_hashref ()

Does the same thing as C<stats_tube> except returns a hashref of the stats instead of the L<Beanstalk:Stats> object.

=cut

sub stats_tube_as_hashref {
    my ($self, $tube_name) = @_; 
    my $stats = $self->stats_tube($tube_name);
    if (defined $stats) {
        my %tube = (name => $tube_name);
        foreach my $key (keys %{$stats}) {
            my $underscore_key = $key;
            $underscore_key =~ s/-/_/g;
            $tube{$underscore_key} = $stats->{$key};
        }
        return \%tube;
    }
    else {
        ouch 440, 'Tube not found.', $tube_name;
    }
}

=head2 stats_job_as_hashref ( id )

Does the same thing as C<stats_job> except returns a hashref of the stats instead of the L<Beanstalk:Stats> object.

=over

=item id

The unique id of the job.

=back

=cut

sub stats_job_as_hashref {
    my ($self, $id) = @_; 
    my $stats = $self->stats_job($id);
    if (defined $stats) {
        my %beanstalk;
        foreach my $key (keys %{$stats}) {
            my $underscore_key = $key;
            $underscore_key =~ s/-/_/g;
            $beanstalk{$underscore_key} = $stats->{$key};
        }
        return \%beanstalk;
    }
    else {
        ouch 440, 'Job '.$id.' not found.', $id;
    }
}

=head2 stats_as_hashref ()

Does the same thing as C<stats> except returns a hashref of the stats instead of the L<Beanstalk:Stats> object.

=cut

sub stats_as_hashref {
    my ($self) = @_; 
    my $stats = $self->stats;
    my %beanstalk;
    foreach my $key (keys %{$stats}) {
        my $underscore_key = $key;
        $underscore_key =~ s/-/_/g;
        $beanstalk{$underscore_key} = $stats->{$key};
    }
    return \%beanstalk;
}

=head2 guess_min_peek_range ( [ options ] )

Returns a best guess as to what the lowest job id might be in the queue.

=over

=item options

A hash reference of options to change the behavior of this method.

=over

=item tubes

An array reference of tubes to search in. Optional. Defaults to all.

=item guess_peek_range

Default 100. The number of elements to use in peek-range guesses.

=item jitter

Default 0.25. Add some jitter in the opposite direction of 1/4 range.

=back

=back

=cut

sub guess_min_peek_range {
    my ($self, $options) = @_;
    my $guess_peek_range = $options->{guess_peek_range} || 100;
    my $jitter = $options->{jitter} || 0.25;
    my @tubes = @{$options->{tubes}} if exists $options->{tubes} && ref $options->{tubes} eq 'ARRAY';
    if (scalar @tubes < 1) {
        @tubes = $self->list_tubes;
    }
    my $min = 0;
    foreach my $tube (@tubes) {
        my $job = $self->peek_ready;
        if (defined $job) {
            if ($min == 0) {
                $min = $job->id;
            }
            else {
                $min = min($min, $job->id);    
            }
        }
    }
    my $jitter_min = ceil(min - ($guess_peek_range * $jitter));
    return max(1, $jitter_min);
}

=head2 guess_max_peek_range ( min, [ options ] ) 

Pick a maximum peek range based on the minimum.

=over

=item min

The result of C<guess_min_peek_range>.

=item options

A hash reference of options to change the behavior of this method.

=over

=item guess_peek_range

Default 100. The number of elements to use in peek-range guesses.

=back

=back

=cut

sub guess_max_peek_range {
    my ($self, $min, $options) = @_;
    my $guess_peek_range = $options->{guess_peek_range} || 100;
    return ($min + $guess_peek_range) - 1;
}

=head1 SEE ALSO

See the B<Plugin Development> section of L<Wingman::Role::Plugin> for details on how to give Wingman functionality.

=cut

1;

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use File::Temp qw(tempdir);
use IO::Socket::INET;
use JSON::XS qw(encode_json decode_json);

# Only broker configuration and logging are supplied; this test never opens MySQL.
BEGIN {
    package SharedBrokerConfig;
    our $server;
    sub get {
        my ($self, $key) = @_;
        return { server => $server, default_tube => 'legacy.test' } if $key eq 'wingman/beanstalkd';
        return 'legacy.test' if $key eq 'wingman/beanstalkd/default_tube';
        return { 'Wingman::Plugin::TriggerWebHook' => { phase => 'TriggerWebHook' } } if $key eq 'wingman/plugins';
        die "Unexpected configuration read: $key";
    }
    package SharedBrokerLog;
    sub info { }
    sub error { }
    package Wing;
    sub config { bless {}, 'SharedBrokerConfig' }
    sub log { bless {}, 'SharedBrokerLog' }
    sub send_templated_email { die 'Autokick must not send an alert for Jobber jobs' }
    $INC{'Wing.pm'} = __FILE__;
}
use Wingman;
use Wing::Command::Command::autokick_jobs;
use Wing::Command::Command::kick;

my $directory = tempdir(CLEANUP => 1);
my $listener = IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => 0, Listen => 1) or die $!;
my $port = $listener->sockport;
close $listener;
$SharedBrokerConfig::server = "127.0.0.1:$port";
my $pid = fork();
die "Cannot fork broker: $!" unless defined $pid;
if (!$pid) {
    exec($ENV{TGC_JOBBER_BEANSTALKD_BINARY} || 'beanstalkd', '-l', '127.0.0.1', '-p', $port, '-b', $directory, '-f', '0');
    die "Cannot start test Beanstalkd: $!";
}
END { my $status = $?; if ($pid) { kill 'TERM', $pid; waitpid($pid, 0); } $? = $status; }
my $ready;
for (1..100) {
    if (my $socket = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port)) { close $socket; $ready = 1; last; }
    select undef, undef, undef, 0.02;
}
BAIL_OUT('Native Beanstalkd did not start') unless $ready;
my $raw = Beanstalk::Client->new({ server => $SharedBrokerConfig::server, default_tube => 'jobber.core' });
my $job = $raw->put({ data => '{"version":1,"operation":"core.bury-me.v1","payload":{}}' });
ok $job, 'created a native Jobber envelope';
$raw->reserve(0)->bury;
my $id = $job->id;
my $wingman = Wingman->new;

is_deeply [sort $wingman->list_tubes], ['default', 'legacy.test'], 'Wingman enumeration excludes Jobber tubes';
for my $call (
    ['use', 'jobber.core'], ['watch', 'jobber.core'], ['watch_only', 'legacy.test', 'jobber.core'],
    ['pause_tube', 'jobber.core', 60], ['peek_buried', 'jobber.core'], ['stats_tube', 'jobber.core'],
    ['put', 'TriggerWebHook', {}, { tube => 'jobber.core' }],
    ['peek', $id], ['kick_job', $id], ['delete', $id], ['bury', $id], ['release', $id], ['touch', $id], ['stats_job', $id],
) {
    my ($method, @args) = @$call;
    my $ok = eval { $wingman->$method(@args); 1 };
    ok !$ok, "$method refuses Jobber ownership";
    like "$@", qr/Jobber/, "$method explains the owning runner";
    is $raw->stats_job($id)->state, 'buried', "$method leaves Jobber state unchanged";
}
is_deeply [$wingman->list_tubes_watched], ['legacy.test'], 'rejected watch_only does not partially change watch state';

my $legacy = $wingman->put('TriggerWebHook', {});
ok $legacy, 'legacy producer still works';
my $reserved = $wingman->reserve(0);
is $reserved->id, $legacy->id, 'legacy worker reserves its own job';
$reserved->bury;
Wing::Command::Command::autokick_jobs->execute({}, []);
is $raw->stats_job($id)->state, 'buried', 'actual autokick leaves Jobber buried';
is $raw->stats_job($legacy->id)->state, 'ready', 'actual autokick still retries legacy jobs';
$wingman->reserve(0)->bury;
Wing::Command::Command::kick->execute({}, []);
is $raw->stats_job($id)->state, 'buried', 'actual bulk kick leaves Jobber buried';
is $raw->stats_job($legacy->id)->state, 'ready', 'bulk kick still retries legacy jobs';
ok $wingman->delete($legacy->id), 'legacy job can still be deleted';

# A direct lower-level client is trusted, but Wingman must not decode or execute its Jobber job.
my $native = $raw->peek($id);
my $ok = eval { $wingman->_instantiate_job($native); 1 };
ok !$ok, 'job instantiation checks ownership before decoding another format';
like "$@", qr/Jobber/, 'instantiation reports ownership instead of a JSON/plugin failure';
is $raw->stats_job($id)->state, 'buried', 'instantiation does not bury, kick or delete foreign work';
$raw->delete($id);
$raw->disconnect;
$wingman->disconnect;
done_testing();

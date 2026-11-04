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
    our $excluded_tubes;
    sub get {
        my ($self, $key) = @_;
        return 'admin@example.test' if $key eq 'wing_admin';
        return $excluded_tubes if $key eq 'wingman/autokick_excluded_tubes';
        return { server => $server, default_tube => 'legacy.test' } if $key eq 'wingman/beanstalkd';
        return 'legacy.test' if $key eq 'wingman/beanstalkd/default_tube';
        return { 'Wingman::Plugin::TriggerWebHook' => { phase => 'TriggerWebHook' } } if $key eq 'wingman/plugins';
        die "Unexpected configuration read: $key";
    }
    package SharedBrokerLog;
    our @messages;
    sub info { push @messages, $_[1] }
    sub error { }
    package Wing;
    sub config { bless {}, 'SharedBrokerConfig' }
    sub log { bless {}, 'SharedBrokerLog' }
    our @alerts;
    sub send_templated_email { shift; push @alerts, [@_] }
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
my $manual = $wingman->put('TriggerWebHook', {}, { tube => 'manual.retained' });
$wingman->watch_only('manual.retained');
$wingman->reserve(0)->bury;
$wingman->watch_only('legacy.test');
$SharedBrokerConfig::excluded_tubes = ['manual.retained'];
Wing::Command::Command::autokick_jobs->execute({}, []);
is $raw->stats_job($manual->id)->state, 'buried', 'excluded manual job remains buried';
is $raw->stats_job($manual->id)->kicks, 0, 'excluded manual job is never kicked';
is scalar @Wing::alerts, 0, 'fresh excluded and foreign jobs do not trigger stuck alerts';
Wing::Command::Command::autokick_jobs->execute({}, []);
is $raw->stats_job($manual->id)->kicks, 0, 'repeated autokick still leaves manual recovery to operators';
my $hidden = $wingman->put('TriggerWebHook', {}, { tube => 'manual.retained' });
$wingman->watch_only('manual.retained');
$wingman->reserve(0)->bury;
{
    local @Wing::alerts;
    Wing::Command::Command::autokick_jobs->execute({}, []);
    is scalar @Wing::alerts, 1, 'multiple fresh retained jobs alert because hidden job details are unknown';
}
for (1..2) {
    $raw->kick_job($hidden->id);
    $wingman->reserve(0)->bury;
}
is $wingman->peek_buried('manual.retained')->id, $manual->id, 'fresh retained job is the buried head';
{
    local @Wing::alerts;
    local @SharedBrokerLog::messages;
    Wing::Command::Command::autokick_jobs->execute({}, []);
    is scalar @Wing::alerts, 1, 'hidden retained jobs trigger an administrator alert';
    ok scalar(grep { /Retained backlog in manual\.retained: 2 buried jobs.*cannot determine.*Inspect.*manual recovery/ }
        @SharedBrokerLog::messages), 'monitoring reports backlog count, uncertainty and operator action';
    is $raw->stats_job($manual->id)->state, 'buried', 'monitoring preserves fresh retained head';
    is $raw->stats_job($manual->id)->kicks, 0, 'monitoring does not kick retained head';
    is $raw->stats_job($hidden->id)->state, 'buried', 'monitoring preserves hidden stuck job';
    is $raw->stats_job($hidden->id)->kicks, 2, 'monitoring does not retry hidden stuck job';
}
$wingman->delete($hidden->id);
$wingman->watch_only('manual.retained');
for (1..2) {
    $raw->kick_job($manual->id);
    $wingman->reserve(0)->bury;
}
$wingman->watch_only('legacy.test');
Wing::Command::Command::autokick_jobs->execute({}, []);
is $raw->stats_job($manual->id)->state, 'buried', 'excluded stuck job stays buried';
is_deeply $Wing::alerts[-1], ['stuck_wingman_job', {
    email => 'admin@example.test', subject => 'Wingman jobs need inspection',
}], 'excluded stuck job still sends the administrator alert';
ok scalar(grep { /Stuck job .* in manual\.retained/ } @SharedBrokerLog::messages),
    'excluded stuck job remains visible in monitoring logs';
$wingman->delete($manual->id);
is $raw->stats_job($id)->state, 'buried', 'actual autokick leaves Jobber buried';
is $raw->stats_job($legacy->id)->state, 'ready', 'actual autokick still retries legacy jobs';
$wingman->reserve(0)->bury;
Wing::Command::Command::kick->execute({}, []);
is $raw->stats_job($id)->state, 'buried', 'actual bulk kick leaves Jobber buried';
is $raw->stats_job($legacy->id)->state, 'ready', 'bulk kick still retries legacy jobs';
ok $wingman->delete($legacy->id), 'legacy job can still be deleted';

my $old = $wingman->put('TriggerWebHook', {}, { tube => 'manual.retained' });
$wingman->watch_only('manual.retained');
$wingman->reserve(0)->bury;
{
    # Model elapsed broker time without waiting twelve hours in the test.
    no warnings qw(redefine once);
    local *Beanstalk::Stats::age = sub { 12*60*60 + 1 };
    local @Wing::alerts;
    local @SharedBrokerLog::messages;
    Wing::Command::Command::autokick_jobs->execute({}, []);
    is scalar @Wing::alerts, 1, 'excluded old job still sends an administrator alert';
    ok scalar(grep { /Old job .* in manual\.retained/ } @SharedBrokerLog::messages),
        'excluded old job remains visible in monitoring logs';
}
is $raw->stats_job($old->id)->state, 'buried', 'excluded old job stays buried';
is $raw->stats_job($old->id)->kicks, 0, 'excluded old job is never kicked';
$wingman->delete($old->id);
{
    local @Wing::alerts;
    Wing::Command::Command::autokick_jobs->execute({}, []);
    is scalar @Wing::alerts, 0, 'empty excluded tube does not trigger an alert';
}
$wingman->watch_only('legacy.test');

for my $configuration (undef, []) {
    local $SharedBrokerConfig::excluded_tubes = $configuration;
    my $automatic = $wingman->put('TriggerWebHook', {});
    $wingman->reserve(0)->bury;
    Wing::Command::Command::autokick_jobs->execute({}, []);
    is $raw->stats_job($automatic->id)->state, 'ready', 'omitted or empty exclusions preserve automatic recovery';
    $wingman->delete($automatic->id);
}

my $untouched = $wingman->put('TriggerWebHook', {});
$wingman->reserve(0)->bury;
for my $invalid ('manual.retained', {}, [''], [undef], [[]]) {
    local $SharedBrokerConfig::excluded_tubes = $invalid;
    my $ok = eval { Wing::Command::Command::autokick_jobs->execute({}, []); 1 };
    ok !$ok, 'malformed autokick exclusion configuration is rejected';
    like "$@", qr/wingman\/autokick_excluded_tubes must be an array of non-empty tube names/,
        'configuration error explains how to fix the exclusion list';
    is $raw->stats_job($untouched->id)->state, 'buried', 'invalid policy stops before retrying any jobs';
}

$wingman->delete($untouched->id);

for my $format (qw(txt html)) {
    my $path = "$FindBin::Bin/../var/init/var/mkits/stuck_wingman_job.mkit/body.$format";
    open my $body, '<', $path or die "Cannot read email template $path: $!";
    local $/;
    my $text = <$body>;
    like $text, qr/jobs.*need inspection/, 'alert describes inspection without claiming hidden jobs are stuck';
    like $text, qr/autokick_jobs/, 'alert tells operators where to get backlog details';
}


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

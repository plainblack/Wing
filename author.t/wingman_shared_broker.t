use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use Config::JSON;
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
        return { server => $server, default_tube => 'wingman_test.legacy' } if $key eq 'wingman/beanstalkd';
        return 'wingman_test.legacy' if $key eq 'wingman/beanstalkd/default_tube';
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

$SharedBrokerConfig::server = Config::JSON->new($ENV{WING_CONFIG})->get('wingman/beanstalkd/server');
# The dev broker is shared, so monitoring and bulk kicks here only see tubes this test owns.
my $all_tubes = Wingman->can('list_tubes');
{
    no warnings 'redefine';
    *Wingman::list_tubes = sub { grep { /^wingman_test\.|^jobber\.wingman_test$/ } $all_tubes->(@_) };
}
my $raw = Beanstalk::Client->new({ server => $SharedBrokerConfig::server, default_tube => 'jobber.wingman_test' });
my $job = $raw->put({ data => '{"version":1,"operation":"core.bury-me.v1","payload":{}}' });
ok $job, 'created a native Jobber envelope';
$raw->reserve(0)->bury;
my $id = $job->id;
my $wingman = Wingman->new;

is_deeply [$wingman->list_tubes], ['wingman_test.legacy'], 'Wingman enumeration excludes Jobber tubes';
for my $call (
    ['use', 'jobber.wingman_test'], ['watch', 'jobber.wingman_test'], ['watch_only', 'wingman_test.legacy', 'jobber.wingman_test'],
    ['pause_tube', 'jobber.wingman_test', 60], ['peek_buried', 'jobber.wingman_test'], ['stats_tube', 'jobber.wingman_test'],
    ['put', 'TriggerWebHook', {}, { tube => 'jobber.wingman_test' }],
    ['peek', $id], ['kick_job', $id], ['delete', $id], ['bury', $id], ['release', $id], ['touch', $id], ['stats_job', $id],
) {
    my ($method, @args) = @$call;
    my $ok = eval { $wingman->$method(@args); 1 };
    ok !$ok, "$method refuses Jobber ownership";
    like "$@", qr/Jobber/, "$method explains the owning runner";
    is $raw->stats_job($id)->state, 'buried', "$method leaves Jobber state unchanged";
}
is_deeply [$wingman->list_tubes_watched], ['wingman_test.legacy'], 'rejected watch_only does not partially change watch state';

my $legacy = $wingman->put('TriggerWebHook', {});
ok $legacy, 'legacy producer still works';
my $reserved = $wingman->reserve(0);
is $reserved->id, $legacy->id, 'legacy worker reserves its own job';
$reserved->delete;
my $manual = $wingman->put('TriggerWebHook', {}, { tube => 'wingman_test.manual' });
$wingman->watch_only('wingman_test.manual');
$wingman->reserve(0)->bury;
$wingman->watch_only('wingman_test.legacy');
$SharedBrokerConfig::excluded_tubes = ['wingman_test.manual'];
Wing::Command::Command::autokick_jobs->execute({}, []);
is $raw->stats_job($manual->id)->state, 'buried', 'excluded manual job remains buried';
is $raw->stats_job($manual->id)->kicks, 0, 'excluded manual job is never kicked';
is scalar @Wing::alerts, 0, 'fresh excluded and foreign jobs do not trigger stuck alerts';
Wing::Command::Command::autokick_jobs->execute({}, []);
is $raw->stats_job($manual->id)->kicks, 0, 'repeated autokick still leaves manual recovery to operators';
my $hidden = $wingman->put('TriggerWebHook', {}, { tube => 'wingman_test.manual' });
$wingman->watch_only('wingman_test.manual');
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
is $wingman->peek_buried('wingman_test.manual')->id, $manual->id, 'fresh retained job is the buried head';
{
    local @Wing::alerts;
    local @SharedBrokerLog::messages;
    Wing::Command::Command::autokick_jobs->execute({}, []);
    is scalar @Wing::alerts, 1, 'hidden retained jobs trigger an administrator alert';
    ok scalar(grep { /Retained backlog in wingman_test\.manual: 2 buried jobs.*cannot determine.*Inspect.*manual recovery/ }
        @SharedBrokerLog::messages), 'monitoring reports backlog count, uncertainty and operator action';
    is $raw->stats_job($manual->id)->state, 'buried', 'monitoring preserves fresh retained head';
    is $raw->stats_job($manual->id)->kicks, 0, 'monitoring does not kick retained head';
    is $raw->stats_job($hidden->id)->state, 'buried', 'monitoring preserves hidden stuck job';
    is $raw->stats_job($hidden->id)->kicks, 2, 'monitoring does not retry hidden stuck job';
}
$wingman->delete($hidden->id);
$wingman->watch_only('wingman_test.manual');
for (1..2) {
    $raw->kick_job($manual->id);
    $wingman->reserve(0)->bury;
}
$wingman->watch_only('wingman_test.legacy');
Wing::Command::Command::autokick_jobs->execute({}, []);
is $raw->stats_job($manual->id)->state, 'buried', 'excluded stuck job stays buried';
is_deeply $Wing::alerts[-1], ['stuck_wingman_job', {
    email => 'admin@example.test', subject => 'Wingman jobs need inspection',
}], 'excluded stuck job still sends the administrator alert';
ok scalar(grep { /Stuck job .* in wingman_test\.manual/ } @SharedBrokerLog::messages),
    'excluded stuck job remains visible in monitoring logs';
$wingman->delete($manual->id);
is $raw->stats_job($id)->state, 'buried', 'actual autokick leaves Jobber buried';
$legacy = $wingman->put('TriggerWebHook', {});
$wingman->reserve(0)->bury;
Wing::Command::Command::autokick_jobs->execute({}, []);
is $raw->stats_job($legacy->id)->state, 'buried', 'monitor leaves legacy buried work for selective manual recovery';
Wing::Command::Command::kick->execute({}, []);
is $raw->stats_job($id)->state, 'buried', 'actual bulk kick leaves Jobber buried';
is $raw->stats_job($legacy->id)->state, 'ready', 'bulk kick still retries legacy jobs';
ok $wingman->delete($legacy->id), 'legacy job can still be deleted';

my $old = $wingman->put('TriggerWebHook', {}, { tube => 'wingman_test.manual' });
$wingman->watch_only('wingman_test.manual');
$wingman->reserve(0)->bury;
{
    # Model elapsed broker time without waiting twelve hours in the test.
    no warnings qw(redefine once);
    local *Beanstalk::Stats::age = sub { 12*60*60 + 1 };
    local @Wing::alerts;
    local @SharedBrokerLog::messages;
    Wing::Command::Command::autokick_jobs->execute({}, []);
    is scalar @Wing::alerts, 1, 'excluded old job still sends an administrator alert';
    ok scalar(grep { /Old job .* in wingman_test\.manual/ } @SharedBrokerLog::messages),
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
$wingman->watch_only('wingman_test.legacy');

for my $configuration (undef, []) {
    local $SharedBrokerConfig::excluded_tubes = $configuration;
    my $automatic = $wingman->put('TriggerWebHook', {});
    $wingman->reserve(0)->bury;
    Wing::Command::Command::autokick_jobs->execute({}, []);
    is $raw->stats_job($automatic->id)->state, 'buried', 'omitted or empty exclusions do not revive terminal work';
    $wingman->delete($automatic->id);
}

my $untouched = $wingman->put('TriggerWebHook', {});
$wingman->reserve(0)->bury;
for my $invalid ('wingman_test.manual', {}, [''], [undef], [[]]) {
    local $SharedBrokerConfig::excluded_tubes = $invalid;
    my $ok = eval { Wing::Command::Command::autokick_jobs->execute({}, []); 1 };
    ok !$ok, 'malformed autokick exclusion configuration is rejected';
    like "$@", qr/wingman\/autokick_excluded_tubes must be an array of non-empty tube names/,
        'configuration error explains how to fix the exclusion list';
    is $raw->stats_job($untouched->id)->state, 'buried', 'invalid policy stops before retrying any jobs';
}

my $stuck_first = $wingman->put('TriggerWebHook', {}, { tube => 'wingman_test.aaa' });
$wingman->watch_only('wingman_test.aaa');
$wingman->reserve(0)->bury;
for (1..2) {
    $raw->kick_job($stuck_first->id);
    $wingman->reserve(0)->bury;
}
for my $error ('NOT_FOUND', 'INTERNAL_ERROR') {
    my $later = $wingman->put('TriggerWebHook', {}, { tube => 'wingman_test.zzz' });
    $wingman->watch_only('wingman_test.zzz');
    $wingman->reserve(0)->bury;
    my $stats_tube = Beanstalk::Client->can('stats_tube');
    my $list_tubes = Beanstalk::Client->can('list_tubes');
    no warnings 'redefine';
    local *Beanstalk::Client::list_tubes = sub { sort $list_tubes->(@_) };
    local *Beanstalk::Client::stats_tube = sub {
        my ($client, $tube) = @_;
        if ($tube eq 'wingman_test.manual') {
            $client->error($error);
            return undef;
        }
        return $stats_tube->(@_);
    };
    local @Wing::alerts;
    local @SharedBrokerLog::messages;
    local $SharedBrokerConfig::excluded_tubes = ['wingman_test.manual'];
    $wingman->use('wingman_test.manual');
    my $ok = eval { Wing::Command::Command::autokick_jobs->execute({}, []); 1 };
    if ($error eq 'NOT_FOUND') {
        ok $ok, 'disappeared retained tube does not abort monitoring';
    }
    else {
        ok !$ok, 'broker statistics failure makes the command fail visibly';
        like "$@", qr/INTERNAL_ERROR.*Check the broker/, 'statistics failure gives an actionable cause';
    }
    is scalar @Wing::alerts, 1, 'statistics failure does not suppress an earlier stuck-job alert';
    is $raw->stats_job($later->id)->state, 'buried', 'statistics failure does not mutate later tubes';
    ok scalar(grep { /Buried backlog in wingman_test\.zzz/ } @SharedBrokerLog::messages),
        'statistics failure does not skip monitoring later tubes';
    $wingman->delete($later->id);
}
for my $method (qw(peek_buried stats_job)) {
    my $later = $wingman->put('TriggerWebHook', {}, {tube => 'wingman_test.zzz'});
    $wingman->watch_only('wingman_test.zzz');
    $wingman->reserve(0)->bury;
    my $original = Beanstalk::Client->can($method);
    no warnings 'redefine';
    no strict 'refs';
    local *{"Beanstalk::Client::$method"} = sub {
        my ($client, $job_id) = @_;
        if (($method eq 'peek_buried' && $client->list_tube_used eq 'wingman_test.aaa')
                || ($method eq 'stats_job' && $job_id == $stuck_first->id)) {
            $client->error('INTERNAL_ERROR');
            return undef;
        }
        return $original->(@_);
    };
    local @Wing::alerts;
    local @SharedBrokerLog::messages;
    my $ok = eval { Wing::Command::Command::autokick_jobs->execute({}, []); 1 };
    ok !$ok, "$method failure makes monitoring fail visibly";
    like "$@", qr/INTERNAL_ERROR.*Check the broker/, "$method failure names the broker cause and recovery action";
    is scalar @Wing::alerts, 1, "$method failure preserves the detected administrator alert";
    ok scalar(grep { /Buried backlog in wingman_test\.zzz/ } @SharedBrokerLog::messages),
        "$method failure does not prevent later monitoring";
    is $raw->stats_job($later->id)->state, 'buried', "$method failure does not revive later jobs";
    $wingman->delete($later->id);
}
$wingman->delete($stuck_first->id);
$wingman->delete($untouched->id);

my $fresh_terminal = $wingman->put('TriggerWebHook', {}, {tube => 'wingman_test.terminal'});
$wingman->watch_only('wingman_test.terminal');
$wingman->reserve(0)->bury;
{
    local @Wing::alerts;
    Wing::Command::Command::autokick_jobs->execute({}, []);
    is $raw->stats_job($fresh_terminal->id)->state, 'buried', 'monitor never revives a fresh terminal job';
    is $raw->stats_job($fresh_terminal->id)->kicks, 0, 'monitor does not increment terminal retry counters';
    is scalar @Wing::alerts, 1, 'fresh terminal work in an ordinary tube requests operator inspection';
}
$wingman->delete($fresh_terminal->id);

for my $payload ('not JSON', '["UninstalledPlugin",{}]') {
    $raw->use('wingman_test.unloaded');
    $raw->watch_only('wingman_test.unloaded');
    my $unknown = $raw->put({data => $payload});
    $raw->reserve(0)->bury;
    my $ok = eval { Wing::Command::Command::autokick_jobs->execute({}, []); 1 };
    ok $ok, 'monitor inspects native metadata without decoding or loading the plugin';
    is $raw->stats_job($unknown->id)->state, 'buried', 'unloaded or malformed work remains retained';
    is $raw->stats_job($unknown->id)->kicks, 0, 'monitor never kicks unloaded or malformed work';
    $raw->delete($unknown->id);
}

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

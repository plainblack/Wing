use strict;
use warnings;
use FindBin;
use Test::More;
use Config::JSON;
use File::Temp qw(tempdir);
use JSON::XS qw(encode_json);
use Beanstalk::Client;

my $server = Config::JSON->new($ENV{WING_CONFIG})->get('wingman/beanstalkd/server');
my $client = Beanstalk::Client->new({server => $server, default_tube => 'wingman_test.cli'});
$client->use('0');
$client->watch_only('0');
# Tube 0 is not namespaced on the shared dev broker, so only use it while it is empty.
my $existing = $client->stats_tube('0');
die "Tube 0 on the dev broker already holds jobs. This test needs it empty; remove them if an earlier Wing test run left them.\n"
    if grep { $existing->$_ } qw(current_jobs_ready current_jobs_reserved current_jobs_delayed current_jobs_buried);
my $job = $client->put({data => 'not a Wingman payload'});
END { $client->delete($job->id) if $job }
$client->reserve(0)->bury;
my $directory = tempdir(CLEANUP => 1);
open my $log, '>', "$directory/log.conf" or die $!;
print $log "log4perl.logger = ERROR, screen\nlog4perl.appender.screen = Log::Log4perl::Appender::Screen\nlog4perl.appender.screen.layout = SimpleLayout\n";
close $log;
my $path = "$directory/config.json";
open my $config, '>', $path or die $!;
my $serialized = encode_json({
    app_namespace => 'TestWing', api_key_permissions => [], db => ['dbi:SQLite:dbname=:memory:', '', ''],
    log4perl_config => "$directory/log.conf",
    cache => {driver => 'Memory', global => 1},
    wingman => {beanstalkd => {server => $server, default_tube => 'wingman_test.cli'},
        autokick_excluded_tubes => ['0']},
});
print $config $serialized;
close $config;
{
    local $ENV{WING_HOME} = "$FindBin::Bin/..";
    local $ENV{WING_APP} = $FindBin::Bin;
    local $ENV{WING_OWNER} = $FindBin::Bin;
    local $ENV{WING_CONFIG} = $path;
    # The dev broker is shared, so alerts about other tubes' buried jobs are logged, not mailed.
    local $ENV{WING_NO_EMAIL} = 1;
    is system($^X, "$FindBin::Bin/../bin/wing", 'autokick_jobs'), 0,
        'actual CLI monitors a valid zero-named retained tube without loading its malformed job';
}
open my $unchanged, '<', $path or die $!;
is do { local $/; <$unchanged> }, $serialized, 'CLI configuration is unchanged';
close $unchanged;
is $client->stats_job($job->id)->state, 'buried', 'actual CLI retains the native job';
is $client->stats_job($job->id)->kicks, 0, 'actual CLI never kicks the native job';
done_testing;

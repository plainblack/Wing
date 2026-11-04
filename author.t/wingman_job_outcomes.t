use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use IO::Socket::INET;
use Beanstalk::Client;
use Wingman::Job;

{
    package OutcomePlugin;
    sub new { bless { run => $_[1] }, $_[0] }
    sub run { $_[0]->{run}->($_[1]) }
}

my $listener = IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => 0, Listen => 1) or die $!;
my $port = $listener->sockport;
close $listener;
my $pid = fork();
die "Cannot fork broker: $!" unless defined $pid;
if (!$pid) {
    exec 'beanstalkd', '-l', '127.0.0.1', '-p', $port;
    die "Cannot start Beanstalkd: $!";
}
END { my $status = $?; if ($pid) { kill 'TERM', $pid; waitpid $pid, 0; } $? = $status; }
{
    local $SIG{ALRM} = sub { die 'Test broker did not become ready' };
    alarm 15;
    until (my $socket = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port)) { }
    alarm 0;
}
my $client = Beanstalk::Client->new({ server => "127.0.0.1:$port", default_tube => 'wing.outcomes' });
my (@info, @errors);
no warnings 'redefine';
local *Wingman::Job::log_info = sub { push @info, $_[2] };
local *Wingman::Job::log_error = sub { push @errors, $_[2] };

sub run_job {
    my ($callback) = @_;
    @info = (); @errors = ();
    my $queued = $client->put({ data => '{}' });
    my $reserved = $client->reserve(0);
    my $job = Wingman::Job->new(beanstalk_job => $reserved,
        wingman_plugin => OutcomePlugin->new($callback), job_args => {});
    return ($job->run, $queued->id);
}

my ($out, $id) = run_job(sub {
    my ($job) = @_;
    $client->delete($job->id);
    return { wingman_outcome => 'failed', message => 'Deletion was not acknowledged; reconcile delivery before retrying.' }
        unless $job->delete;
});
is $out->{wingman_outcome}, 'failed', 'false deletion returns explicit failure';
ok !grep($_ eq 'Job complete.', @info), 'false deletion is not announced as completion';
like join(' ', @errors), qr/\Q$id\E.*reconcile delivery/, 'failure names job and preserves recovery instruction';

($out, $id) = run_job(sub {
    my ($job) = @_;
    local *Beanstalk::Client::delete = sub { die "Broker connection lost\n" };
    my $deleted = eval { $job->delete };
    return { wingman_outcome => 'failed', message => "Delete uncertain: $@ Reconcile delivery before retrying." }
        unless $deleted;
});
is $out->{wingman_outcome}, 'failed', 'caught dependency exception remains a failed outcome';
is $client->stats_job($id)->state, 'reserved', 'framework leaves uncertain job reserved without retry or burial';
ok !grep($_ eq 'Job complete.', @info), 'dependency exception is not announced as completion';
like join(' ', @errors), qr/Broker connection lost.*Reconcile delivery/s, 'dependency failure keeps recovery instruction';
like join(' ', @errors), qr/confirm.*retention.*broker may redeliver/i,
    'uncertain acknowledgement warns that plugin must confirm its retention policy';
$client->disconnect;
$client = Beanstalk::Client->new({ server => "127.0.0.1:$port", default_tube => 'wing.outcomes' });
is $client->reserve(5)->id, $id, 'broker redelivers unretained failure after worker disconnect';
$client->delete($id);

($out, $id) = run_job(sub {
    my ($job) = @_;
    $job->bury or die 'Could not confirm plugin retention';
    local *Beanstalk::Client::delete = sub { die "Broker connection lost\n" };
    eval { $job->delete };
    return { wingman_outcome => 'failed', message => 'Delete uncertain; reconcile buried job before retrying.' };
});
$client->disconnect;
$client = Beanstalk::Client->new({ server => "127.0.0.1:$port", default_tube => 'wing.outcomes' });
is $client->stats_job($id)->state, 'buried', 'plugin-confirmed failure retention survives worker disconnect';
ok !grep($_ eq 'Job complete.', @info), 'retained failed acknowledgement is not completion';
$client->delete($id);

($out, $id) = run_job(sub {
    my ($job) = @_;
    return { wingman_outcome => $job->delete ? 'complete' : 'failed', message => 'Reconcile failed deletion.' };
});
is $out->{wingman_outcome}, 'complete', 'confirmed true deletion returns completion';
ok !defined($client->stats_job($id)), 'completed job is absent from broker';
ok grep($_ eq 'Job complete.', @info), 'confirmed deletion is announced as complete';
is scalar @errors, 0, 'successful acknowledgement does not log an error';

($out, $id) = run_job(sub {
    $_[0]->bury;
    return { wingman_outcome => 'retained' };
});
is $client->stats_job($id)->state, 'buried', 'intentional retention preserves worker burial policy';
ok grep($_ eq 'Job retained.', @info), 'retention is described as retention';
ok !grep($_ eq 'Job complete.', @info), 'retention does not manufacture completion';
is scalar @errors, 0, 'documented retention is not an error';
$client->delete($id);

for my $legacy (undef, 0, 'legacy output', { answer => 42 }) {
    ($out, $id) = run_job(sub { $_[0]->delete; return $legacy });
    is_deeply $out, $legacy, 'legacy plugin result is preserved';
    ok grep($_ eq 'Job complete.', @info), 'legacy completion logging remains compatible';
}

($out, $id) = run_job(sub { return { wingman_outcome => 'failed' } });
like join(' ', @errors), qr/failed outcome requires.*message/i, 'malformed failure tells plugin author what to fix';
$client->delete($id);
$client->disconnect;
done_testing;

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib", "$FindBin::Bin/../lib";
use Test::More;
use Wing;
use Wingman;
use Wingman::Plugin::SendTemplatedEmail;
use Wingman::Plugin::EmailAllAdmins;
use Wing::Command::Command::autokick_jobs;

my $shipped = Config::JSON->new("$FindBin::Bin/../var/init/etc/wing.conf");
ok scalar(grep { $_ eq $shipped->get('wingman/email_tube') }
    @{$shipped->get('wingman/autokick_excluded_tubes')}),
    'shipped config keeps its email tube out of autokick';
my $worker = Wingman->new;
my $client = $worker->beanstalk;
my $tube = $client->list_tube_used;
my $config = Wing->config;
{
    package EmailAckConfig;
    our ($original, $excluded);
    sub get {
        return $excluded if $_[1] eq 'wingman/autokick_excluded_tubes';
        return { 'Wingman::Plugin::SendTemplatedEmail' => {phase => 'SendTemplatedEmail'} }
            if $_[1] eq 'wingman/plugins';
        return $original->get($_[1]);
    }
}
$EmailAckConfig::original = $config;
$EmailAckConfig::excluded = [$tube];
my (@info, @errors, $sends);
no warnings 'redefine';
local *Wing::config = sub { bless {}, 'EmailAckConfig' };
local *Wing::send_templated_email = sub { ++$sends; return 1 };
local *Wingman::Job::log_info = sub { push @info, $_[2] };
local *Wingman::Job::log_error = sub { push @errors, $_[2] };
my $queued = $client->put({}, 'SendTemplatedEmail', { template => 'generic', params => {}, options => {} });
my $job = Wingman::Job->new(beanstalk_job => $client->reserve(0),
    wingman_plugin => Wingman::Plugin::SendTemplatedEmail->new,
    job_args => { template => 'generic', params => {}, options => {} });
my $out;
{
    local *Beanstalk::Client::delete = sub { $_[0]->error('Deletion response unavailable'); return undef };
    $out = $job->run;
}
is ref($out) eq 'HASH' ? $out->{wingman_outcome} : undef, 'failed', 'unacknowledged deletion reports failure';
is $sends, 1, 'SMTP boundary accepted once';
ok !grep($_ eq 'Job complete.', @info), 'unacknowledged deletion never logs completion';
like join(' ', @errors), qr/@{[$job->id]}.*[Rr]econcile/s, 'error names job and reconciliation action';
$client->disconnect;
my $observer = Beanstalk::Client->new($config->get('wingman/beanstalkd'));
is $observer->stats_job($job->id)->state, 'buried', 'manual retention survives actual worker disconnect';
Wing::Command::Command::autokick_jobs->execute({}, []);
is $observer->stats_job($job->id)->state, 'buried', 'actual autokick preserves email retention';
is $observer->stats_job($job->id)->kicks, 0, 'autokick never retries retained email';
$observer->delete($job->id);
$observer->disconnect;
my @admins;
END { $_->delete for grep { $_->in_storage } @admins; }
push @admins, Wing->db->resultset('User')->create({
    username => 'email_ack_seed', email => 'email_ack_seed@example.invalid', admin => 1 });
push @admins, map {
    Wing->db->resultset('User')->create({ username => "email_ack_$_", email => "email_ack_$_\@example.invalid", admin => 1 })
} 1..2;
my $admin_count = Wing->db->resultset('User')->search({admin => 1})->count;
for my $plugin ('SendTemplatedEmail', 'EmailAllAdmins') {
    subtest "$plugin / no email_tube or autokick_excluded_tubes" => sub {
        @info = (); @errors = (); $sends = 0;
        $EmailAckConfig::excluded = undef;
        ok !defined Wing->config->get('wingman/email_tube'), 'config has no email_tube';
        my $worker_client = Beanstalk::Client->new($config->get('wingman/beanstalkd'));
        my $queued = $worker_client->put({ data => '{}' });
        my $class = 'Wingman::Plugin::'.$plugin;
        my $job = Wingman::Job->new(beanstalk_job => $worker_client->reserve(0),
            wingman_plugin => $class->new,
            job_args => { template => 'generic', params => {}, options => {} });
        is $job->run->{wingman_outcome}, 'complete', 'queued email completes';
        is $sends, $plugin eq 'EmailAllAdmins' ? $admin_count : 1, 'queued email is delivered';
        is_deeply \@errors, [], 'no configuration error is logged';
        ok !defined $worker_client->stats_job($queued->id), 'delivered job is deleted';
        $worker_client->disconnect;
    };
}
my $delete = Beanstalk::Client->can('delete');
my $bury = Beanstalk::Client->can('bury');
for my $plugin ('SendTemplatedEmail', 'EmailAllAdmins') {
    for my $mode ('true', 'false', 'throw', 'lost_response', 'delivery_throw', 'bury_false', 'bury_throw') {
        subtest "$plugin / $mode" => sub {
            @info = (); @errors = (); $sends = 0;
            my $worker_client = Beanstalk::Client->new($config->get('wingman/beanstalkd'));
            my $publisher = Beanstalk::Client->new({
                %{$config->get('wingman/beanstalkd')}, default_tube => 'wingman_test.children' });
            my @children;
            my $parent = $worker_client->put({ data => '{}' });
            my $class = 'Wingman::Plugin::'.$plugin;
            my $job = Wingman::Job->new(beanstalk_job => $worker_client->reserve(0),
                wingman_plugin => $class->new,
                job_args => { template => 'generic', params => {}, options => {} });
            my $boundary_state;
            local *Wing::send_templated_email = sub {
                ++$sends;
                $boundary_state = $publisher->stats_job($job->id)->state;
                if ($plugin eq 'EmailAllAdmins') {
                    ok $_[3]->{wingman}, 'fan-out publishes background children';
                    push @children, $publisher->put({ data => 'controlled child publication' });
                }
                die "Delivery response lost after acceptance\n" if $mode eq 'delivery_throw';
                return 1;
            };
            my $out;
            {
                local *Beanstalk::Client::delete = sub {
                    return $delete->(@_) if $mode eq 'true';
                    $delete->(@_) if $mode eq 'lost_response';
                    die "Deletion response lost\n" if $mode eq 'throw' || $mode eq 'lost_response';
                    $_[0]->error('Deletion response unavailable');
                    return undef;
                };
                local *Beanstalk::Client::bury = sub {
                    die "Burial response lost\n" if $mode eq 'bury_throw';
                    return undef if $mode eq 'bury_false';
                    return $bury->(@_);
                };
                $out = eval { $job->run };
                is "$@", '', 'no exception escapes into framework retry or burial';
            }
            my $preflight_failed = $mode =~ /^bury_/;
            is $sends || 0, $preflight_failed ? 0 : $mode eq 'delivery_throw' ? 1
                : $plugin eq 'EmailAllAdmins' ? $admin_count : 1, 'only intended irreversible effects occur';
            is $boundary_state, 'buried', 'broker retention confirmed before effects' unless $preflight_failed;
            is $out->{wingman_outcome}, $mode eq 'true' ? 'complete' : 'failed', 'explicit queue outcome';
            is scalar(grep { $_ eq 'Job complete.' } @info), $mode eq 'true' ? 1 : 0, 'completion requires true deletion';
            if ($mode ne 'true') {
                like join(' ', @errors), qr/@{[$job->id]}/, 'failure includes job identity';
                like join(' ', @errors), $preflight_failed ? qr/before retrying/
                    : qr/Reconcile.*SMTP.*child/s, 'actionable recovery instruction';
            }
            $worker_client->disconnect;
            my $state = $publisher->stats_job($job->id);
            if ($mode eq 'true' || $mode eq 'lost_response') {
                ok !defined $state, 'acknowledged or response-lost deletion leaves no broker job';
            }
            else {
                is $state->state, $preflight_failed ? 'ready' : 'buried', 'actual worker disconnect preserves intended broker state';
                is $state->buries, $preflight_failed ? 0 : 1, 'framework adds no accidental burial';
                $publisher->delete($job->id);
            }
            is scalar @children, $plugin eq 'EmailAllAdmins' && !$preflight_failed
                ? ($mode eq 'delivery_throw' ? 1 : $admin_count) : 0, 'native child publication count matches fan-out';
            for my $child (@children) {
                is $publisher->stats_job($child->id)->state, 'ready', 'published child remains available once';
                $publisher->delete($child->id);
            }
            $publisher->disconnect;
        };
    }
}
$_->delete for @admins;
done_testing;

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

# The dev broker is shared, so autokick here only sees tubes this test owns.
my $all_tubes = Wingman->can('list_tubes');
{
    no warnings 'redefine';
    *Wingman::list_tubes = sub { grep { /^wingman_test(\.|$)/ } $all_tubes->(@_) };
}
my $worker = Wingman->new;
my $client = $worker->beanstalk;
my $tube = $client->list_tube_used;
my $config = Wing->config;
{
    package EmailAckConfig;
    our ($original, $excluded);
    sub get {
        return $excluded if $_[1] eq 'wingman/autokick_excluded_tubes';
        return 'email_ack_admin@example.invalid' if $_[1] eq 'wing_admin';
        return { 'Wingman::Plugin::SendTemplatedEmail' => {phase => 'SendTemplatedEmail'} }
            if $_[1] eq 'wingman/plugins';
        return $original->get($_[1]);
    }
}
$EmailAckConfig::original = $config;
$EmailAckConfig::excluded = [$tube];
my (@info, @errors, @warnings, @alerts, $sends);
no warnings 'redefine';
local *Wing::config = sub { bless {}, 'EmailAckConfig' };
my $real_send_templated_email = Wing->can('send_templated_email');
local *Wing::send_templated_email = sub { push(@alerts, $_[2]), return 1 if $_[1] eq 'stuck_wingman_job'; ++$sends; return 1 };
local *Wingman::Job::log_info = sub { push @info, $_[2] };
local *Wingman::Job::log_error = sub { push @errors, $_[2] };
local *Wingman::Job::log_warn = sub { push @warnings, $_[2] };
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
is scalar @alerts, 1, 'admin is alerted about the unacknowledged deletion';
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
        local $EmailAckConfig::excluded = undef;
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
    for my $mode ('true', 'false', 'throw', 'lost_response', 'delivery_throw', 'bad_address', 'alert_throw', 'bury_false', 'bury_throw') {
        subtest "$plugin / $mode" => sub {
            @info = (); @errors = (); @warnings = (); @alerts = (); $sends = 0;
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
                if ($_[1] eq 'stuck_wingman_job') {
                    push @alerts, $_[2];
                    die "Alert SMTP unavailable\n" if $mode eq 'alert_throw';
                    return 1;
                }
                ++$sends;
                $boundary_state = $publisher->stats_job($job->id)->state;
                if ($plugin eq 'EmailAllAdmins') {
                    ok $_[3]->{wingman}, 'fan-out publishes background children';
                    push @children, $publisher->put({ data => 'controlled child publication' });
                }
                die "Delivery response lost after acceptance\n" if $mode eq 'delivery_throw' || $mode eq 'alert_throw';
                Ouch::ouch(442, 'Illegal email address for this user.', 'email') if $mode eq 'bad_address';
                return 1;
            };
            my $out;
            {
                local *Beanstalk::Client::delete = sub {
                    return $delete->(@_) if $mode eq 'true' || $mode eq 'bad_address';
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
            my $failed_delivery = $mode =~ /^(delivery|alert)_throw$/ || ($mode eq 'bad_address' && $plugin eq 'EmailAllAdmins');
            my $deleted_bad_address = $mode eq 'bad_address' && $plugin eq 'SendTemplatedEmail';
            my $succeeded = $mode eq 'true' || $deleted_bad_address;
            is $sends || 0, $preflight_failed ? 0 : $failed_delivery || $deleted_bad_address ? 1
                : $plugin eq 'EmailAllAdmins' ? $admin_count : 1, 'only intended irreversible effects occur';
            is $boundary_state, 'buried', 'broker retention confirmed before effects' unless $preflight_failed;
            is $out->{wingman_outcome}, $succeeded ? 'complete' : 'failed', 'explicit queue outcome';
            is scalar(grep { $_ eq 'Job complete.' } @info), $succeeded ? 1 : 0, 'completion requires true deletion';
            if ($deleted_bad_address) {
                like join(' ', @warnings), qr/Illegal email address/, 'bad address is logged as a warning';
            }
            else {
                is_deeply \@warnings, [], 'no bad-address warning';
            }
            if ($succeeded || $preflight_failed) {
                is_deeply \@alerts, [], 'no admin alert when nothing is left buried';
            }
            else {
                is scalar @alerts, 1, 'admin is alerted about the buried job';
                is $alerts[0]{email}, 'email_ack_admin@example.invalid', 'alert goes to wing_admin';
                like $alerts[0]{subject}, qr/@{[$job->id]}/, 'alert subject names the job';
            }
            like join(' ', @errors), qr/alert also failed.*Alert SMTP unavailable/s, 'failed alert is logged'
                if $mode eq 'alert_throw';
            if (!$succeeded) {
                like join(' ', @errors), qr/@{[$job->id]}/, 'failure includes job identity';
                like join(' ', @errors), $preflight_failed ? qr/before retrying/
                    : qr/Reconcile.*SMTP.*child/s, 'actionable recovery instruction';
            }
            $worker_client->disconnect;
            my $state = $publisher->stats_job($job->id);
            if ($succeeded || $mode eq 'lost_response') {
                ok !defined $state, 'acknowledged or response-lost deletion leaves no broker job';
            }
            else {
                is $state->state, $preflight_failed ? 'ready' : 'buried', 'actual worker disconnect preserves intended broker state';
                is $state->buries, $preflight_failed ? 0 : 1, 'framework adds no accidental burial';
                $publisher->delete($job->id);
            }
            is scalar @children, $plugin eq 'EmailAllAdmins' && !$preflight_failed
                ? ($failed_delivery ? 1 : $admin_count) : 0, 'native child publication count matches fan-out';
            for my $child (@children) {
                is $publisher->stats_job($child->id)->state, 'ready', 'published child remains available once';
                $publisher->delete($child->id);
            }
            $publisher->disconnect;
        };
    }
}
for my $smtp (['Permanent', 550], ['Temporary', 450]) {
    my ($kind, $code) = @$smtp;
    subtest "SendTemplatedEmail / SMTP $code recipient rejection" => sub {
        @info = (); @errors = (); @warnings = ();
        my @sent;
        my $original_mkits = $config->get('mkits');
        $config->set('mkits', "$FindBin::Bin/../var/init/var/mkits/");
        my $original_smtp = $config->get('smtp');
        $config->set('smtp', {host => 'smtp.example.invalid'});
        local *Wing::send_templated_email = $real_send_templated_email;
        local *Email::Sender::Simple::send = sub {
            my $to = $_[1]->header('To');
            push @sent, $to;
            # The failure Email::Sender::Transport::SMTP throws when RCPT is refused.
            "Email::Sender::Failure::$kind"->throw(message => "$code mailbox unavailable",
                code => $code, recipients => ['rejected@example.invalid'])
                if $to =~ /rejected\@example\.invalid/;
            return 1;
        };
        my $worker_client = Beanstalk::Client->new($config->get('wingman/beanstalkd'));
        my $queued = $worker_client->put({ data => '{}' });
        my $job = Wingman::Job->new(beanstalk_job => $worker_client->reserve(0),
            wingman_plugin => Wingman::Plugin::SendTemplatedEmail->new,
            job_args => { template => 'generic', options => {},
                params => { subject => 'Rejected', message => 'Rejected', me => { email => 'rejected@example.invalid' } } });
        my $out = eval { $job->run };
        is "$@", '', 'no exception escapes';
        $config->set('mkits', $original_mkits);
        $config->set('smtp', $original_smtp);
        if ($kind eq 'Permanent') {
            is $out->{wingman_outcome}, 'complete', 'rejected address completes';
            like join(' ', @warnings), qr/rejected/i, 'rejected address is logged as a warning';
            ok !defined $worker_client->stats_job($queued->id), 'rejected address job is deleted';
            is_deeply \@sent, ['rejected@example.invalid'], 'no admin alert';
        }
        else {
            is $out->{wingman_outcome}, 'failed', 'temporary rejection fails';
            is_deeply \@warnings, [], 'temporary rejection is not a bad address';
            is $worker_client->stats_job($queued->id)->state, 'buried', 'temporary rejection stays buried';
            is_deeply \@sent, ['rejected@example.invalid', 'email_ack_admin@example.invalid'], 'admin is alerted';
            $worker_client->delete($queued->id);
        }
        $worker_client->disconnect;
    };
}
$_->delete for @admins;
done_testing;

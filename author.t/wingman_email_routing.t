use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib", "$FindBin::Bin/../lib";
use Test::More;
use Wing;
use Wingman;
use Wing::Command;
use App::Cmd::Tester;
use Wing::Command::Command::autokick_jobs;

my $shipped = Config::JSON->new("$FindBin::Bin/../var/init/etc/wing.conf");
is $shipped->get('wingman/email_tube'), 'wingman.email', 'stock installation dedicates an email tube';
is_deeply $shipped->get('wingman/autokick_excluded_tubes'), ['wingman.email'], 'stock default jobs keep automatic recovery';

my $settings = Wing->config->get('wingman');
local $settings->{plugins} = {
    'Wingman::Plugin::SendTemplatedEmail' => {phase => 'SendTemplatedEmail'},
    'Wingman::Plugin::EmailAllAdmins' => {phase => 'EmailAllAdmins'},
    'TestWing::Wingman::HelloWorld' => {phase => 'howdy'},
};
local $settings->{email_tube} = 'wingman.email';
my $worker = Wingman->new;
my $job = $worker->put('SendTemplatedEmail', {template => 'generic', params => {}, options => {}});
is $job->stats->tube, 'wingman.email', 'direct email publication uses installation email tube';
$job->delete;
$worker->disconnect;

# The helper and both plugin phases share routing, while explicit destinations win.
for my $tube (undef, 'mail.installation') {
    local $settings->{email_tube} = $tube;
    my $publisher = Wingman->new;
    my $expected = defined $tube ? 'mail.installation' : 'wingman_test';
    for my $phase ('SendTemplatedEmail', 'EmailAllAdmins', 'howdy') {
        my $options = {priority => 123, ttr => 80};
        my $queued = $publisher->put($phase, {}, $options);
        is $queued->stats->tube, $phase eq 'howdy' ? 'wingman_test' : $expected, "$phase uses intended default";
        is $queued->stats->pri, 123, 'priority preserved';
        is_deeply $options, {priority => 123, ttr => 80}, 'caller queue options unchanged';
        $queued->delete;
        $queued = $publisher->put($phase, {}, {tube => 'caller.explicit'});
        is $queued->stats->tube, 'caller.explicit', 'explicit tube wins';
        $queued->delete;
    }
    Wing->send_templated_email('generic', {}, {wingman => 1});
    my $queued = $publisher->peek_ready($expected);
    ok $queued, 'Wing helper publishes email';
    is $queued->stats->tube, $expected, 'helper uses intended email default';
    $queued->delete;
    Wing->send_templated_email('generic', {}, {wingman => 1, wingman_job_options => {tube => 'caller.explicit'}});
    $queued = $publisher->peek_ready('caller.explicit');
    ok $queued, 'helper preserves explicit caller tube';
    $queued->delete;
    $publisher->disconnect;
}
{
    local $settings->{plugins}{'Wingman::Plugin::SendTemplatedEmail'} = {phase => 'MailAlias'};
    my $publisher = Wingman->new;
    my $queued = $publisher->put('MailAlias', {});
    is $queued->stats->tube, 'wingman.email', 'routing follows registered plugin phase';
    $queued->delete;
    $publisher->disconnect;
}
for my $invalid ('', [], {}, 'bad tube', '-mail', 'x' x 201, 'jobber.mail', "mail\n", "caf\x{e9}") {
    local $settings->{email_tube} = $invalid;
    my $publisher = Wingman->new;
    my $before = $publisher->stats->{ 'total-jobs' };
    my @tubes = sort $publisher->list_tubes;
    for my $options ({}, {tube => 'caller.explicit'}) {
        eval { $publisher->put('SendTemplatedEmail', {}, $options) };
        like "$@", qr{wingman/email_tube must be}, 'invalid installation setting fails even with explicit override';
    }
    is $publisher->stats->{'total-jobs'}, $before, 'bad configuration publishes no jobs';
    is_deeply [sort $publisher->list_tubes], \@tubes, 'bad configuration creates no tubes';
    $publisher->disconnect;
}

for my $explicit (0, 1) {
    my @args = ('do', $explicit ? ('--tube=cli.explicit') : (), 'SendTemplatedEmail', '{}');
    my $result = test_app('Wing::Command' => \@args);
    is $result->error, undef, 'CLI publication succeeds';
    my $publisher = Wingman->new;
    my $queued = $publisher->peek_ready($explicit ? 'cli.explicit' : 'wingman.email');
    ok $queued, 'CLI honors email default and explicit override';
    $queued->delete;
    $publisher->disconnect;
}

{
    my $publisher = Wingman->new;
    eval { $publisher->put('SendTemplatedEmail', {invalid => bless({}, 'UnencodableMail')}) };
    like "$@", qr/encountered object/, 'email publication fails at actual JSON encoder';
    my $normal = $publisher->put('howdy', {});
    is $normal->stats->tube, 'wingman_test', 'failed email cannot divert later ordinary jobs';
    $normal->delete;
    $publisher->disconnect;
}
{
    local $settings->{beanstalkd}{default_tube};
    my $result = test_app('Wing::Command' => ['do', 'howdy', '{}']);
    is $result->error, undef, 'legacy CLI works without configured default tube';
    my $observer = Beanstalk::Client->new($settings->{beanstalkd});
    $observer->use('wingman');
    my $queued = $observer->peek_ready;
    ok $queued, 'non-email CLI preserves legacy wingman destination without configured default';
    $queued->delete if $queued;
    $observer->disconnect;
}

# Execute the real daemon program once without forking; control only its lifecycle.
use Daemon::Control;
use Parallel::ForkManager;
my $program;
{
    no warnings 'redefine';
    local *Daemon::Control::run = sub { $program = $_[0]->program };
    local @ARGV;
    do "$FindBin::Bin/../bin/wingman.pl";
    die $@ if $@;
}
local $settings->{max_workers} = 0;
local $settings->{autokick_excluded_tubes} = ['wingman.email'];
my $sender = Wingman->new;
my $admin = Wing->db->resultset('User')->create({username => 'email_route_admin', email => 'route@example.invalid', admin => 1});
my $parent = $sender->put('EmailAllAdmins', {template => 'generic', params => {}});
{
    no warnings 'redefine';
    local *Parallel::ForkManager::finish = sub { die "one worker completed\n" };
    local $SIG{ALRM} = sub { die "Worker did not consume configured email tube\n" };
    alarm 5;
    eval { $program->() };
    alarm 0;
    is $@, "one worker completed\n", 'default worker consumes configured email tube';
}
ok !defined $parent->stats, 'admin parent confirms deletion after actual fan-out';
$admin->delete;
my $child = $sender->peek_ready('wingman.email');
ok $child, 'admin child publication uses email tube';
is $child->stats->tube, 'wingman.email', 'actual fan-out child is routed';
{
    my $config = Wing->config;
    my $original_mkits = $config->get('mkits');
    my $original_smtp = $config->get('smtp');
    $config->set('smtp', {host => 'smtp.example.invalid'});
    $config->set('mkits', "$FindBin::Bin/var/mkits/");
    my $accepted = 0;
    no warnings 'redefine';
    local *Email::Sender::Simple::send = sub {
        ++$accepted;
        is $child->stats->state, 'buried', 'actual email plugin confirms burial before SMTP boundary';
        return 1;
    };
    $sender->watch_only('wingman.email');
    my $outcome = $sender->reserve(0)->run;
    is $outcome->{wingman_outcome}, 'complete', 'actual SMTP path completes with acknowledged deletion';
    is $accepted, 1, 'one SMTP acceptance for fan-out child';
    ok !defined $child->stats, 'child deletion acknowledged';
    $config->set('mkits', $original_mkits);
    $config->set('smtp', $original_smtp);
}
# Retain an email failure while retrying an unrelated job through actual autokick.
my $email = $sender->put('SendTemplatedEmail', {});
$sender->watch_only('wingman.email');
$sender->reserve(0)->bury;
my $ordinary = $sender->put('howdy', {});
$sender->watch_only('wingman_test');
$sender->reserve(0)->bury;
Wing::Command::Command::autokick_jobs->execute({}, []);
is $email->stats->state, 'buried', 'autokick retains dedicated email job';
is $email->stats->kicks, 0, 'email never automatically retried';
is $ordinary->stats->state, 'ready', 'autokick recovers unrelated default job';
is $ordinary->stats->kicks, 1, 'default job automatically retried';
$email->delete;
$ordinary->delete;
{
    no warnings 'redefine';
    local *Daemon::Control::run = sub { $program = $_[0]->program };
    local @ARGV = ('--watch-only=wingman_test');
    do "$FindBin::Bin/../bin/wingman.pl";
    die $@ if $@;
    my $mail = $sender->put('SendTemplatedEmail', {}, {priority => 0});
    my $normal = $sender->put('howdy', {});
    local *Parallel::ForkManager::finish = sub { die "one worker completed\n" };
    local $SIG{ALRM} = sub { die "Explicit worker watch test hung\n" };
    alarm 5;
    eval { $program->() };
    alarm 0;
    is $@, "one worker completed\n", 'explicit worker watch completes default job';
    ok !defined $normal->stats, 'explicitly watched default job ran';
    is $mail->stats->state, 'ready', 'explicit watch list replaces automatic email watch';
    $mail->delete;
}
$sender->disconnect;
done_testing;

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib", "$FindBin::Bin/../lib";
use Test::More;
use Wing;
use Wingman;
use Wing::Command::Command::autokick_jobs;

# The dev broker is shared, so autokick here only sees tubes this test owns.
my $all_tubes = Wingman->can('list_tubes');
{
    no warnings 'redefine';
    *Wingman::list_tubes = sub { grep { /^wingman_test(\.|$)/ } $all_tubes->(@_) };
}
my $config = Wing->config->config;
local $config->{mkits} = "$FindBin::Bin/../var/init/var/mkits/";
local $config->{smtp} = {host => 'smtp.example.invalid'};
local $config->{wing_admin} = 'email_admin@example.invalid';
local $config->{wingman}{plugins} = {
    'Wingman::Plugin::SendTemplatedEmail' => {phase => 'SendTemplatedEmail'},
    'Wingman::Plugin::EmailAllAdmins' => {phase => 'EmailAllAdmins'},
};

# SMTP outcome per recipient: undef accepts, otherwise the Email::Sender failure and code to throw.
my (%refuse, @sent, @warnings);
my $real_send = \&Email::Sender::Simple::send;
no warnings 'redefine';
local *Email::Sender::Simple::send = sub {
    my $to = $_[1]->header('To');
    push @sent, $to;
    # Email::Sender itself refuses a To with no parseable address, before any SMTP.
    return $real_send->(@_) unless $to =~ /\@/;
    my ($kind, $code) = @{$refuse{$to} || []};
    # The failure Email::Sender::Transport::SMTP throws when RCPT is refused.
    "Email::Sender::Failure::$kind"->throw(message => "$code mailbox unavailable",
        code => $code, recipients => [$to]) if $kind;
    return 1;
};
local *Wingman::Job::log_warn = sub { push @warnings, $_[2] };
use warnings 'redefine';

my $wingman = Wingman->new;
my $queue = sub {
    my ($email) = @_;
    $wingman->put('SendTemplatedEmail', {template => 'generic', options => {},
        params => {subject => 'Hello', message => 'Hello', me => {email => $email}}});
    return $wingman->reserve(0);
};

subtest 'a templated email is sent and its job deleted' => sub {
    @sent = ();
    my $job = $queue->('sent@example.invalid');
    $job->run;
    is_deeply \@sent, ['sent@example.invalid'], 'email sent once';
    ok !defined $wingman->stats_job($job->id), 'job deleted after sending';
};

subtest 'a permanent SMTP refusal (Ouch 442) deletes the job' => sub {
    @sent = (); @warnings = ();
    local $refuse{'refused@example.invalid'} = ['Permanent', 550];
    my $job = $queue->('refused@example.invalid');
    $job->run;
    ok !defined $wingman->stats_job($job->id), 'refused address job deleted';
    like join(' ', @warnings), qr/rejected/i, 'refusal logged as a warning';
};

subtest 'an unparseable recipient address (Ouch 442) deletes the job' => sub {
    @warnings = ();
    my $job = $queue->('nobodyexample.com');
    $job->run;
    ok !defined $wingman->stats_job($job->id), 'unparseable address job deleted';
    like join(' ', @warnings), qr/no recipients/, 'refusal logged as a warning';
};

subtest 'another send failure buries the job, autokick retries it, then alerts wing_admin' => sub {
    @sent = ();
    local $refuse{'later@example.invalid'} = ['Temporary', 450];
    my $job = $queue->('later@example.invalid');
    ok !eval { $job->run; 1 }, 'failure is raised to the worker';
    like "$@", qr/450 mailbox unavailable/, 'raised error names the SMTP failure';
    is $wingman->stats_job($job->id)->state, 'buried', 'failed email job is buried';
    for my $kick (1, 2) {
        Wing::Command::Command::autokick_jobs->execute({}, []);
        my $stats = $wingman->stats_job($job->id);
        is $stats->state, 'ready', "autokick kicks the fresh buried email job (kick $kick)";
        is $stats->kicks, $kick, "kick $kick is counted";
        eval { $wingman->reserve(0)->run };
        is $wingman->stats_job($job->id)->state, 'buried', "retry $kick fails and buries again";
    }
    @sent = ();
    Wing::Command::Command::autokick_jobs->execute({}, []);
    is $wingman->stats_job($job->id)->state, 'buried', 'job kicked twice stays buried';
    is_deeply \@sent, ['email_admin@example.invalid'], 'wing_admin is alerted about the stuck job';
    $wingman->delete($job->id);
};

subtest 'EmailAllAdmins publishes one email per admin, then deletes its job' => sub {
    my $admin = Wing->db->resultset('User')->create({username => 'email_admin', email => 'admin@example.invalid', admin => 1});
    $wingman->put('EmailAllAdmins', {template => 'generic', params => {subject => 'Hi', message => 'Hi'}});
    my $parent = $wingman->reserve(0);
    $parent->run;
    $admin->delete;
    ok !defined $wingman->stats_job($parent->id), 'parent job deleted';
    my $child = $wingman->reserve(0);
    is $child->job_args->{params}{me}{email}, 'admin@example.invalid', 'child email queued for the admin';
    $child->delete;
};

$wingman->disconnect;
done_testing;

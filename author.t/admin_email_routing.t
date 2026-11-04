use strict;
use warnings;
use Test::More import => ['!pass'];
use FindBin;
use File::Temp qw(tempdir);
use JSON qw(encode_json decode_json);
use Dancer ':syntax';
use Wing;
use Wingman;
use Test::TCP;
use HTTP::Server::PSGI;
use Dancer::Handler;

set views => "$FindBin::Bin/../var/init/views";
set public => "$FindBin::Bin/../public";
set engines => {template_toolkit => {start_tag => '[%', end_tag => '%]'}};
set template => 'template_toolkit';
set show_errors => 1;
my $settings = Wing->config->get('wingman');
$settings->{email_tube} = 'wingman.email';
$settings->{autokick_excluded_tubes} = ['wingman.email'];
$settings->{plugins} = {
    'Wingman::Plugin::EmailAllAdmins' => {phase => 'EmailAllAdmins'},
    'Wingman::Plugin::SendTemplatedEmail' => {phase => 'SendTemplatedEmail'},
    'TestWing::Wingman::HelloWorld' => {phase => 'howdy'},
};
my $admin = Wing->db->resultset('User')->create({username => 'routing-admin', admin => 1});
my $session = $admin->start_session({sso => 0});
my $directory = tempdir(CLEANUP => 1);
open my $fixture, '>', "$directory/input.json" or die $!;
print $fixture encode_json({session => $session->id});
close $fixture;
my $publisher = Wingman->new;
$publisher->use('admin.viewed');
for my $scenario ('configured', 'aliases', 'legacy-null', 'legacy-absent', 'missing-plugin') {
    $settings->{plugins}{'Wingman::Plugin::EmailAllAdmins'}{phase} = $scenario eq 'aliases' ? 'AdminMailAlias' : 'EmailAllAdmins';
    $settings->{plugins}{'Wingman::Plugin::SendTemplatedEmail'}{phase} = $scenario eq 'aliases' ? 'MailAlias' : 'SendTemplatedEmail';
    $settings->{email_tube} = $scenario =~ /^legacy/ ? undef : 'wingman.email';
    delete $settings->{email_tube} if $scenario eq 'legacy-absent';
    delete $settings->{plugins}{'Wingman::Plugin::SendTemplatedEmail'} if $scenario eq 'missing-plugin';
    my $api = Test::TCP->new(code => sub {
        my $port = shift;
        require Wing::Rest::Wingman;
        HTTP::Server::PSGI->new(host => '127.0.0.1', port => $port)->run(Dancer::Handler->get_handler->psgi_app);
    });
    my $server = Test::TCP->new(code => sub {
        my $port = shift;
        require Wing::Web::Admin::Wingman;
        HTTP::Server::PSGI->new(host => '127.0.0.1', port => $port)->run(Dancer::Handler->get_handler->psgi_app);
    });
    my $status = system('node', "$FindBin::Bin/browser/admin-email-routing.cjs", $server->port, $directory, $api->port, $scenario);
    is $status, 0, 'mounted admin submission selects intended email destination';
    if (-f "$directory/jobs-$scenario.json") {
        open my $results, '<', "$directory/jobs-$scenario.json" or die $!;
        my $jobs = decode_json(do { local $/; <$results> });
        for my $job (@$jobs) {
            my $queued = $publisher->beanstalk->peek($job->{id});
            is $queued->stats->tube, $job->{tube}, "$job->{phase}: native broker destination";
            $queued->delete;
        }
    }
    undef $server;
    undef $api;
}
$publisher->disconnect;
done_testing;

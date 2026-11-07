use strict;
use warnings;
use Test::More import => ['!pass'];
use FindBin;
use JSON qw(encode_json decode_json);
use HTTP::Tiny;
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
$settings->{plugins} = {
    'Wingman::Plugin::EmailAllAdmins' => {phase => 'EmailAllAdmins'},
    'Wingman::Plugin::SendTemplatedEmail' => {phase => 'SendTemplatedEmail'},
    'TestWing::Wingman::HelloWorld' => {phase => 'howdy'},
};
my $publisher = Wingman->new;
my $viewed = 'wingman_test.viewed';
$publisher->use($viewed);
for my $scenario ('configured', 'aliases', 'legacy-null', 'legacy-absent', 'missing-plugin') {
    $settings->{plugins}{'Wingman::Plugin::EmailAllAdmins'}{phase} = $scenario eq 'aliases' ? 'AdminMailAlias' : 'EmailAllAdmins';
    $settings->{plugins}{'Wingman::Plugin::SendTemplatedEmail'}{phase} = $scenario eq 'aliases' ? 'MailAlias' : 'SendTemplatedEmail';
    $settings->{email_tube} = $scenario =~ /^legacy/ ? undef : 'wingman_test.email';
    delete $settings->{email_tube} if $scenario eq 'legacy-absent';
    delete $settings->{plugins}{'Wingman::Plugin::SendTemplatedEmail'} if $scenario eq 'missing-plugin';
    # REST calls are rate limited per user, so each scenario signs in its own admin.
    my $admin = Wing->db->resultset('User')->create({username => "routing-$scenario", email => "routing-$scenario\@example.invalid", admin => 1});
    my $http = HTTP::Tiny->new(default_headers => {Cookie => 'session_id='.$admin->start_session({sso => 0})->id});
    # Wing's web and REST routes cannot share a process; each child inherits this scenario's settings.
    my $api = Test::TCP->new(code => sub {
        my $port = shift;
        require Wing::Rest::Wingman;
        HTTP::Server::PSGI->new(host => '127.0.0.1', port => $port)->run(Dancer::Handler->get_handler->psgi_app);
    });
    my $web = Test::TCP->new(code => sub {
        my $port = shift;
        require Wing::Web::Admin::Wingman;
        HTTP::Server::PSGI->new(host => '127.0.0.1', port => $port)->run(Dancer::Handler->get_handler->psgi_app);
    });
    my $api_uri = 'http://127.0.0.1:'.$api->port;
    my $page = $http->get('http://127.0.0.1:'.$web->port."/admin/wingman/tubes/$viewed");
    is $page->{status}, 200, "$scenario: tube page renders";
    my %page_phases = map { $_ => 1 } grep { length } $page->{content} =~ /data-email-(?:admin|template)-phase="([^"]*)"/g;
    my $submit = sub {
        my ($phase) = @_;
        # The page drops its tube for the email phases it was given, as wingman_tube.tt does.
        my %job = (phase => $phase, arguments => '{}', $page_phases{$phase} ? () : (tube => $viewed));
        return $http->post_form("$api_uri/api/wingman/jobs", \%job);
    };
    if ($scenario eq 'missing-plugin') {
        ok !$page_phases{''}, 'blank phase is not a registered email phase';
        my $refused = $submit->('');
        is $refused->{status}, 442, 'unregistered phase is refused';
        is decode_json($refused->{content})->{error}{code}, 442, 'refusal carries its error code';
        next;
    }
    my @email_phases = $scenario eq 'aliases' ? ('AdminMailAlias', 'MailAlias') : ('EmailAllAdmins', 'SendTemplatedEmail');
    is_deeply [sort keys %page_phases], [sort @email_phases], "$scenario: page knows the configured email phases";
    my %routed;
    for my $phase (@email_phases, 'howdy', $email_phases[0], 'howdy') {
        my $email = grep { $_ eq $phase } @email_phases;
        my $response = $submit->($phase);
        is $response->{status}, 200, "$phase: submission accepted";
        my $id = decode_json($response->{content})->{result}{id};
        my $tube = !$email ? $viewed : $scenario =~ /^legacy/ ? 'wingman_test' : 'wingman_test.email';
        is $publisher->beanstalk->peek($id)->stats->tube, $tube, "$phase: native broker destination";
        $routed{$id} = $tube;
    }
    my $listed = decode_json($http->get("$api_uri/api/wingman/tubes/$viewed/jobs")->{content})->{result}{items};
    is_deeply [sort map { $_->{id} } @$listed], [sort grep { $routed{$_} eq $viewed } keys %routed],
        "$scenario: the viewed tube lists its own jobs and not the email routed elsewhere";
    $publisher->beanstalk->delete($_) for keys %routed;
}
$publisher->disconnect;
done_testing;

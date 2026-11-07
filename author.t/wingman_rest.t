use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Wing;
use Wing::Rest::Wingman;
use Wing::Rest::NotFound;
use Plack::Test;
use Dancer::Handler;
use HTTP::Request::Common qw(GET POST DELETE);
use JSON qw(decode_json);

set show_errors => 0;
set logger => 'null';
my $andy = Wing->db->resultset('User')->create({username => 'andy', email => 'andy@shawshank.jail', admin => 1});
my $session = $andy->start_session({sso => 0})->id;
test_psgi(Dancer::Handler->get_handler->psgi_app, sub {
    my $request = shift;
    my $call = sub { decode_json($request->(shift)->content)->{result} };
    my $job = $call->(POST 'http://localhost/api/wingman/jobs', [session_id => $session, phase => 'howdy', ttr => 60]);
    ok $job->{id} > 0, 'can create a job';
    $job = $call->(GET "http://localhost/api/wingman/jobs/$job->{id}?session_id=$session");
    ok $job->{id} > 0, 'can peek a specific job';
    my $state = $job->{state};
    is $call->(GET "http://localhost/api/wingman/jobs/$state?session_id=$session")->{state}, $state, 'can fetch a job by state';
    ok scalar(@{$call->(GET "http://localhost/api/wingman/tubes/$job->{tube}/jobs?session_id=$session")->{items}}) > 0,
        'got the jobs of a tube';
    ok scalar(@{$call->(GET "http://localhost/api/wingman/tubes?session_id=$session")->{items}}) > 0, 'got the list of tubes';
    is $call->(DELETE "http://localhost/api/wingman/jobs/$job->{id}?session_id=$session")->{success}, 1, 'can delete a job';
});
done_testing();

use lib '/data/Wing/author.t/lib', '/data/Wing/lib';
use Wing::Perl;
use Test::More;

use Wing::Rest::Wingman;
use Wing::Rest::Session;
use Wing::Rest::NotFound;
use TestHelper;
use Test::Wing::Client;

my $wing = Test::Wing::Client->new();

my $andy = TestHelper::init($wing)->{result};

my $job = $wing->post('wingman/jobs', { session_id => $andy->{id}, phase => 'howdy', ttr => 60 });
ok $job->{id} > 0, 'can create a job';

$job = $wing->get('wingman/jobs/'.$job->{id}, { session_id => $andy->{id} });
ok $job->{id} > 0, 'can peek a specific job';

my $state = $job->{state};
$job = $wing->get('wingman/jobs/'.$state, { session_id => $andy->{id} });
is $job->{state}, $state, 'can fetch a job by state';

my $jobs = $wing->get('wingman/tubes/'.$job->{tube}.'/jobs', { session_id => $andy->{id} });
ok scalar(@{$jobs->{items}}) > 0, 'got the jobs of a tube';

my $tubes = $wing->get('wingman/tubes', { session_id => $andy->{id} });
ok scalar(@{$tubes->{items}}) > 0, 'got the list of tubes';

$job = $wing->delete('wingman/jobs/'.$job->{id}, { session_id => $andy->{id} });
is $job->{success}, 1, 'can delete a job';




done_testing();

END {
    TestHelper::cleanup();
}

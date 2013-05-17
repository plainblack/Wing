use lib '/data/Wing/author.t/lib', '/data/Wing/lib';
use Wing::Perl;
use Test::More;

use Wing::Rest::Wingman;
use Wing::Rest::Session;
use Wing::Rest::NotFound;
use TestHelper;

my $andy = TestHelper::init()->{result};

my $job = TestHelper::call('POST','/api/wingman/jobs', { session_id => $andy->{id}, phase => 'howdy', ttr => 60 })->{result};
ok $job->{id} > 0, 'can create a job';

$job = TestHelper::call('GET','/api/wingman/jobs/'.$job->{id}, { session_id => $andy->{id} })->{result};
ok $job->{id} > 0, 'can peek a specific job';

my $state = $job->{state};
$job = TestHelper::call('GET','/api/wingman/jobs/'.$state, { session_id => $andy->{id} })->{result};
is $job->{state}, $state, 'can fetch a job by state';

my $jobs = TestHelper::call('GET','/api/wingman/tubes/'.$job->{tube}.'/jobs', { session_id => $andy->{id} })->{result};
ok scalar(@{$jobs->{items}}) > 0, 'got the jobs of a tube';

my $tubes = TestHelper::call('GET','/api/wingman/tubes', { session_id => $andy->{id} })->{result};
ok scalar(@{$tubes->{items}}) > 0, 'got the list of tubes';

$job = TestHelper::call('DELETE','/api/wingman/jobs/'.$job->{id}, { session_id => $andy->{id} })->{result};
is $job->{success}, 1, 'can delete a job';




done_testing();

END {
    TestHelper::cleanup();
}

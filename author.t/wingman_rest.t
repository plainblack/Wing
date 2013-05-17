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


done_testing();

END {
    TestHelper::cleanup();
}

use lib '/data/Wing/author.t/lib','/data/Wing/lib';
use Test::More;
use Wing::Perl;
use Wing;
use Ouch;

use_ok 'Wingman';

my $wingman = Wingman->new;

isa_ok $wingman, 'Wingman';


eval {  $wingman->put('Invalid') } ;
is $@->code, 442, 'cannot add invalid jobs';



$wingman->put('howdy');


my $job = $wingman->peek_ready;
is ref $job, 'Wingman::Job', 'peek_ready returns a job';



my $job = $wingman->reserve;
is ref $job, 'Wingman::Job', 'its a wingman job';
is ref $job->wingman_plugin, 'TestWing::Wingman::HelloWorld', 'can add Hello World job';
is $job->run, 'Hello World', 'Hello World';


$wingman->put('EchoJson',{foo => 'bar'});
$job = $wingman->reserve;
is ref $job->wingman_plugin, 'TestWing::Wingman::EchoJson', 'can add Echo Json job';
is $job->run, '{"foo":"bar"}', 'echo args as json';


ok $wingman->stats_as_hashref->{total_jobs} > 0, 'stats_as_hashref';
ok $wingman->stats_tube_as_hashref('wingman_test')->{total_jobs} > 0, 'stats_tube_as_hashref';

$job = $wingman->put('howdy');
$wingman->reserve->bury;
ok $wingman->reserve_job($job->id), 'reserve_job reserves a buried job by id';
is $wingman->stats_job($job->id)->state, 'reserved', 'reserve_job leaves the job reserved';
$wingman->delete($job->id);
is $wingman->reserve_job($job->id), undef, 'reserve_job returns undef for a missing job';
is $wingman->error, 'NOT_FOUND', 'reserve_job sets error to the broker response';

done_testing;

END {
}

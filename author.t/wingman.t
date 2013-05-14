use lib '/data/Wing/author.t/lib','/data/Wing/lib';
use Test::More;
use Wing::Perl;
use Wing;
use Ouch;

use_ok 'Wingman';

my $wingman = Wingman->new;

isa_ok $wingman, 'Wingman';

is $wingman->stats->current_jobs_ready, 0, 'zero jobs';


eval {  $wingman->add_job('Invalid') } ;
is $@->code, 442, 'cannot add invalid jobs';


is $wingman->stats->current_jobs_ready, 0, 'zero jobs';


$wingman->add_job('howdy');
is $wingman->stats->current_jobs_ready, 1, 'one job';
my $job = $wingman->next_job;
is ref $job, 'Wingman::Job', 'its a wingman job';
is ref $job->wingman_plugin, 'TestWing::Wingman::HelloWorld', 'can add Hello World job';
is $job->run, 'Hello World', 'Hello World';

is $wingman->stats->current_jobs_ready, 0, 'zero jobs';

$wingman->add_job('EchoJson',{foo => 'bar'});
is $wingman->stats->current_jobs_ready, 1, 'one job';
$job = $wingman->next_job;
is ref $job->wingman_plugin, 'TestWing::Wingman::EchoJson', 'can add Echo Json job';
is $job->run, '{"foo":"bar"}', 'echo args as json';

is $wingman->stats->current_jobs_ready, 0, 'zero jobs';

done_testing;

END {
}

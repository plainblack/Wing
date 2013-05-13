use lib '/data/Wing/author.t/lib','/data/Wing/lib';
use Test::More;
use Wing::Perl;
use Wing;
use Ouch;

use_ok 'TestWing::Wingman::HelloWorld';

is TestWing::Wingman::HelloWorld->new->run, 'Hello World', 'hello world';

use_ok 'TestWing::Wingman::EchoJson';

is TestWing::Wingman::EchoJson->new->run({foo => 'bar'}), '{"foo":"bar"}', 'echo args as json';

use_ok 'Wingman';

my $wingman = Wingman->new;

isa_ok $wingman, 'Wingman';

eval {  $wingman->add_job('Invalid') } ;
is $@->code, 442, 'cannot add invalid jobs';

$wingman->add_job('EchoJson',{foo => 'bar'});
my $job = $wingman->next_job;
is ref $job, 'Wingman::Job', 'its a wingman job';
is ref $job->wingman_plugin, 'TestWing::Wingman::EchoJson', 'can add a job';
is $job->run, '{"foo":"bar"}', 'job produces expected result';
$job->release;

done_testing;

END {
}

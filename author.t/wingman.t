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

done_testing;

END {
}

use lib '/data/Wing/author.t/lib','/data/Wing/lib';
use Test::More;
use Wing::Perl;
use Wing;
use Ouch;

use_ok 'Wingman';

my $wingman = Wingman->new;

isa_ok $wingman, 'Wingman';


$wingman->put('SendTemplatedEmail', { template => 'generic', params => { me => { display_name => 'rizen', real_name => 'JT', email => 'jt@plainblack.com' }, subject => 'test', message => 'this is a test'} });
my $job = $wingman->reserve;
is ref $job, 'Wingman::Job', 'its a wingman job';
is ref $job->wingman_plugin, 'Wingman::Plugin::SendTemplatedEmail', 'can add SendTemplatedEmail job';
$job->run;
print 'Check jt@plainblack.com for a test message.', "\n";

done_testing;

END {
}

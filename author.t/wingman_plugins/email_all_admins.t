use lib '/data/Wing/author.t/lib','/data/Wing/lib';
use Test::More;
use Wing::Perl;
use Wing;
use Ouch;

use_ok 'Wingman';

my $wingman = Wingman->new;

isa_ok $wingman, 'Wingman';


my $job = $wingman->put('EmailAllAdmins', { template => 'generic', params => { subject => 'test', message => 'this is a test'} });
is ref $job, 'Wingman::Job', 'its a wingman job';
is ref $job->wingman_plugin, 'Wingman::Plugin::EmailAllAdmins', 'can add EmailAllAdmins job';
$job->delete;

done_testing;

END {
}

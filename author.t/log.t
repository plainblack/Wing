use lib '/data/Wing/author.t/lib','/data/Wing/lib';

use Test::More;
use Wing::Perl;

use_ok 'Wing';

Wing->log->error('test');

done_testing();

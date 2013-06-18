use lib '/data/Wing/author.t/lib', '/data/Wing/lib';
use Wing::Perl;
use Test::More;

use Wing::Rest::Status;
use Wing::Rest::NotFound;
use TestHelper;

my $status = TestHelper::call('GET','/api/_test')->{result};
ok exists $status->{tracer}, 'got a tracer back in the description';

my $status2 = TestHelper::call('GET','/api/_test')->{result};
is $status2->{tracer}, $status->{tracer}, 'tracer persists across calls';

done_testing();

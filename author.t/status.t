use lib '/data/Wing/author.t/lib', '/data/Wing/lib';
use Wing::Perl;
use Test::More;
use Test::Wing::Client;

use Wing::Rest::Status;
use Wing::Rest::NotFound;

my $wing = Test::Wing::Client->new();

my $status = $wing->get('_test');
ok exists $status->{tracer}, 'got a tracer back in the description';

my $status2 = $wing->get('_test');
is $status2->{tracer}, $status->{tracer}, 'tracer persists across calls';

done_testing();

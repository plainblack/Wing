use lib '/data/Wing/author.t/lib','/data/Wing/lib';

use Test::More;
use Wing::Perl;
use DateTime;

use_ok 'Wing';

my $config = Wing->config;

isa_ok $config, 'Config::JSON';

my $db = Wing->db;

isa_ok $db, 'TestWing::DB';

my @sources = $db->sources;

is scalar(@sources), 3, 'table count is right';

ok 'Employee' ~~ \@sources, 'we have the tables we think we do';

#say $db->deployment_statements();

done_testing();

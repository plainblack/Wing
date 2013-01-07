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

is scalar(@sources), 6, 'source count is right';

ok 'Employee' ~~ \@sources, 'we have the sources we think we do';

#say $db->deployment_statements();

$db->deploy({ add_drop_table => 1 });

my $tables = $db->storage->dbh->selectcol_arrayref('show tables');

is scalar(@$tables), scalar(@sources), 'table count matches source count';

ok 'employees' ~~ $tables, 'we have the tables we think we do';

my $company = $db->resultset('Company')->new({});
$company->name('Plain Black');
$company->insert;
isa_ok $company, 'TestWing::DB::Result::Company';

ok $company->id, 'object is assigned an id';

my $jt = $company->wing_add_to_employees({});
isa_ok $jt, 'TestWing::DB::Result::Employee';
$jt->name('JT Smith');
$jt->title('CEO');
$jt->salary(1.00);
$jt->insert;

is $company->employees->search(undef,{rows=>1})->single->name, 'JT Smith', 'parent can get child';
is $jt->company->name, 'Plain Black', 'child can get parent on new object';
my $jt2 = $db->resultset('Employee')->find($jt->id);
is $jt->company->name, 'Plain Black', 'child can get parent on fetched object';

my $mac = $jt->wing_add_to_equipment;
isa_ok $mac, 'TestWing::DB::Result::Equipment';
$mac->name('MacBook Pro');
$mac->insert;

is $mac->employee->company->name, 'Plain Black', 'can reverse walk the relationships';




done_testing();

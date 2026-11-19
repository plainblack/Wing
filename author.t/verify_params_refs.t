use strict;
use warnings;
use Test::More;
use Wing;
use JSON;

my $admin = Wing->db->resultset('User')->create({username => 'refs-admin', admin => 1});
my $employee = Wing->db->resultset('Employee')->create({name => 'refs-employee'});
my $injection = {'= 0 OR 1=' => 'x'};
my $refused = sub {
    my ($code, $label) = @_;
    eval { $code->() };
    is ref $@ eq 'Ouch' ? $@->code : "$@", 442, $label;
};

my $equipment = Wing->db->resultset('Equipment')->new({});
$refused->(sub { $equipment->employee_id($injection) }, 'a parent id setter refuses an object');
$refused->(sub { $equipment->verify_posted_params({name => 'drill', employee_id => $injection}, $admin) },
    'verify_posted_params refuses an object parent id');
$refused->(sub { $equipment->verify_posted_params({name => ['drill'], employee_id => $employee->id}, $admin) },
    'verify_posted_params refuses a list for a field');
$equipment->verify_posted_params({name => 'drill', employee_id => $employee->id}, $admin);
is $equipment->employee_id, $employee->id, 'verify_posted_params still takes a plain parent id';
$admin->verify_posted_params({no_email => JSON::true}, $admin);
ok $admin->no_email, 'verify_posted_params still takes a JSON boolean';

done_testing;

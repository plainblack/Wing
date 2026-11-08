use strict;
use warnings;
use Test::More;
use Wing;

my @roles = qw(TrendsLog TrendsLogDaily TrendsLogHourly TrendsLogMonthly TrendsLogYearly);
for my $role (@roles) {
    eval qq{
        package TrendsDeploy::DB::Result::$role;
        use Moose;
        extends 'Wing::DB::Result';
        with 'Wing::Role::Result::$role';
        __PACKAGE__->wing_finalize_class(table_name => '\L$role\E');
        1;
    } or die $@;
}
{
    package TrendsDeploy::DB;
    use Moose;
    extends 'DBIx::Class::Schema';
    __PACKAGE__->register_class($_, "TrendsDeploy::DB::Result::$_") for @roles;
}

my $sql = TrendsDeploy::DB->connect->deployment_statements('MySQL');
for my $table (map { lc } @roles) {
    my ($create) = $sql =~ /(CREATE TABLE $table \(.*?\n\)[^;]*;)/s;
    ok $create, "$table is deployed" or next;
    like $create, qr/DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;\z/, "$table keeps Wing's charset and collation";
    like $create, qr/INDEX idx_date_created /, "$table keeps Wing's date_created index";
    like $create, qr/INDEX idx_date_name_value /, "$table keeps its own trend index";
}

done_testing;

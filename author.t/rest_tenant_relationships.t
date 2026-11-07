use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Wing;
use Plack::Test;
use Dancer::Handler;
use HTTP::Request::Common qw(GET);

set show_errors => 0;
set logger => 'null';

# Give each schema's User one relationship the other lacks.
no warnings 'redefine';
for (['TestWing::DB::Result::User', 'main_only'], ['Acquisitions::DB::Result::User', 'tenant_only']) {
    my ($class, $name) = @$_;
    my $accessors = $class->can('relationship_accessors');
    no strict 'refs';
    *{$class.'::relationship_accessors'} = sub { [@{$accessors->(@_)}, $name] };
    *{$class.'::'.$name} = sub { $_[0]->apikeys };
}
use warnings 'redefine';

require Wing::Rest::User;
require Wing::Rest::NotFound;

my $owner = Wing->db->resultset('User')->create({username => 'tenant-owner', email => 'tenant-owner@example.invalid'});
my $site = Wing->db->resultset('Site')->new({});
$site->name('Relationship Site');
$site->hostname('localhost.localdomain');
$site->shortname('testwing_relationships');
$site->user($owner);
$site->insert;
my $tenant_user = Wing->tenant_db('testwing_relationships')->resultset('User')->search({master_user_id => $owner->id})->single;

my $app = Dancer::Handler->psgi_app;
test_psgi $app, sub {
    my $cb = shift;
    is $cb->(GET 'http://localhost/api/user/'.$owner->id.'/main_only')->code, 200, 'main host serves a main-schema relationship';
    is $cb->(GET 'http://localhost.localdomain/api/user/'.$tenant_user->id.'/tenant_only')->code, 200, 'tenant host serves a tenant-schema relationship';
    is $cb->(GET 'http://localhost.localdomain/api/user/'.$tenant_user->id.'/main_only')->code, 404, 'tenant host has no main-only relationship';
};
done_testing;

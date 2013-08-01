use lib '/data/Wing/author.t/lib', '/data/Wing/lib', '/data/Wing/author.t/tenant_files/lib';
use Wing::Perl;
use Wing::Client;
use Data::GUID;
use Test::More;
use Test::Deep;
use Test::TCP;
use TestHelper;
use Ouch;
use HTTP::CookieJar::LWP;

my $andy = Wing->db->resultset('User')->new({
    username    => 'andy',
    real_name   => 'andy',
    email       => 'andy@shawshank.jail',
    use_as_display_name => 'real_name',
});
$andy->encrypt_and_set_password('Saywatanayo');
$andy->insert;

my $red = Wing->db->resultset('User')->new({
    username    => 'red',
    real_name   => 'red',
    email       => 'red@shawshank.jail',
    use_as_display_name => 'real_name',
});
$red->encrypt_and_set_password('Sonny');
$red->insert;

my $prison = Wing->db->resultset('Site')->new({});
$prison->name('Shawshank Prison');
$prison->hostname('localhost.localdomain');
$prison->shortname('localhost');
$prison->user($andy);
$prison->insert;  ##also builds the tenant db for us

my $site_db = Wing->tenant_db('localhost');

my $guid = Data::GUID->guid_string;
Wing->config->set('tenants/sso_key', $guid);
diag 'Tenant sso key: '.$guid;

my $owner = Test::TCP->new(
    code => sub {
        my $port = shift;
        exec 'perl', './tenant_files/bin/account.pl', $port;
        die "Error execing external account server";
    },
);

Wing->config->set('tenants/sso_hostname', 'http://127.0.0.1:'.$owner->port);
diag 'tenant SSO hostname: http://127.0.0.1:'.$owner->port;

my $username = 'Tommy';
my $password = 'whatever';
my $wing = Wing::Client->new( uri => Wing->config->get('tenants/sso_hostname') );

use Wing::Web::Account;
use Wing::Web::NotFound;
use Test::WWW::Mechanize::Dancer;

my $mech = Test::WWW::Mechanize::Dancer->new(
    appdir => '/data/Wing/author.t/tenant_files',
)->mech;
$mech->cookie_jar(HTTP::CookieJar::LWP->new());

my $tommies = $site_db->resultset('User')->search({ username => 'Tommy', })->count;
is $tommies, 0, 'No Tommy users';

$mech->post_ok('http://localhost.localdomain/login', { login => 'Tommy', password => 'rockAndRollah', });
$mech->content_contains('User not found', 'user not found message in web interface');
$tommies = $site_db->resultset('User')->search({ username => 'Tommy', })->count;
is $tommies, 0, 'No users created on a failed login';
is scalar $mech->cookie_jar->cookies_for('http://localhost.localdomain'), 0, 'no cookie set since there was no login';

my $reds = $site_db->resultset('User')->search({ username => 'red', })->count;
is $reds, 0, 'No red users';

$mech->post_ok('http://localhost.localdomain/login', { login => 'red', password => 'Sonny', });
$reds = $site_db->resultset('User')->search({ username => 'red', })->count;
is $reds, 1, 'red account created via tenantsso';
is scalar $mech->cookie_jar->cookies_for('http://localhost.localdomain'), 1, 'one cookie set for login';
my $tenant_red = $site_db->resultset('User')->search({ username => 'red', })->single;
is $tenant_red->master_user_id, $red->id, 'master_user_id set for red after SSO';

done_testing();

END {
    Wing->config->delete('tenants/sso_key');
    Wing->config->delete('tenants/sso_hostname');
    $prison->delete;
    TestHelper::cleanup;
}

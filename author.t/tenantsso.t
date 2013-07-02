use lib '/data/Wing/author.t/lib', '/data/Wing/lib';
use Wing::Perl;
use Data::GUID;
use Test::More;
use Test::Deep;
use Test::Wing::Client;
use TestHelper;

use Wing::Rest::Session;
use Wing::Rest::NotFound;

my $andy = Wing->db->resultset('User')->new({
    username    => 'andy',
    real_name   => 'andy',
    email       => 'andy@shawshank.jail',
    use_as_display_name => 'real_name',
});
$andy->encrypt_and_set_password('Saywatanayo');
$andy->insert;

my $andrew = Wing->db->resultset('User')->new({
    username    => 'andrew',
    real_name   => 'andy',
    email       => 'andrew@shawshank.jail',
    use_as_display_name => 'real_name',
});
$andrew->encrypt_and_set_password('rita_hayworth');
$andrew->insert;

my $guid = Data::GUID->guid_string;
Wing->config->set('tenant/sso_key', $guid);

my $wing = Test::Wing::Client->new();

my $result;

##Failure testing
eval { $wing->post('session/tenantsso', {}); };
is $@->message, 'You need a tenant sso key.', 'request with missing tenant sso key';

eval { $wing->post('session/tenantsso', {api_key => Data::GUID->guid_string, }); };
is $@->message, 'Wrong tenant sso key', 'request with the wrong sso key';

eval { $wing->post('session/tenantsso', {api_key => $guid, }); };
is $@->message, 'You must specify a password.', 'request with no password';

eval { $wing->post('session/tenantsso', {api_key => $guid, password => 'foo-baz-bar', }); };
is $@->message, 'You must specify a username or user_id.', 'request with no user identifier of any type';

done_testing();

END {
    Wing->config->delete('tenant/sso_key');
    Wing->config->delete('tenant');
    TestHelper::cleanup();
}

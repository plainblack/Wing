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
$andrew->encrypt_and_set_password('Detroit');
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

eval { $wing->post('session/tenantsso', {api_key => $guid, password => 'foo-baz-bar', username => 'warden'}); };
is $@->message, 'User not found.', 'user not found due to no username match';

eval { $wing->post('session/tenantsso', {api_key => $guid, password => 'foo-baz-bar', user_id => Data::GUID->guid_string, }); };
is $@->message, 'User not found.', 'user not found due to no user_id match';

eval { $wing->post('session/tenantsso', {api_key => $guid, password => 'foo-baz-bar', username => 'andy', }); };
is $@->message, 'Password incorrect.', 'user not found due to username/password mismatch';

eval { $wing->post('session/tenantsso', {api_key => $guid, password => 'foo-baz-bar', user_id => $andy->id, }); };
is $@->message, 'Password incorrect.', 'user not found due to user_id/password mismatch';

my $result;
$result = $wing->post('session/tenantsso', {api_key => $guid, password => 'Saywatanayo', user_id => $andy->id, });
cmp_deeply(
    $result,
    superhashof({
        map { $_ => $andy->$_ } qw/id username is_admin display_name real_name email/
    }),
    'Got back the right user properties for andy and not andrew via user_id'
);

$result = $wing->post('session/tenantsso', {api_key => $guid, password => 'Saywatanayo', username => 'andy', });
cmp_deeply(
    $result,
    superhashof({
        map { $_ => $andy->$_ } qw/id username is_admin display_name real_name email/
    }),
    'Got back the right user properties for andy and not andrew via username'
);

done_testing();

END {
    Wing->config->delete('tenant/sso_key');
    Wing->config->delete('tenant');
    TestHelper::cleanup();
}

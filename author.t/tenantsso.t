use strict;
use warnings;
use Test::More import => ['!pass'];
use Test::Deep;
use Dancer ':syntax';
use Wing;
use Data::GUID;
use Wing::Rest::Session;
use Wing::Rest::NotFound;
use Plack::Test;
use Dancer::Handler;
use HTTP::Request::Common qw(POST);
use JSON qw(decode_json);

set show_errors => 0;
set logger => 'null';

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

my $app = Dancer::Handler->get_handler->psgi_app;
sub tenantsso {
    my ($params) = @_;
    my $response;
    test_psgi $app, sub { $response = decode_json($_[0]->(POST 'http://localhost/api/session/tenantsso', [%$params])->content) };
    return $response;
}

my $result;

##Failure testing

is tenantsso({})->{error}{message}, 'Tenant SSO not configured.', 'tenant SSO not configured';

my $guid = Data::GUID->guid_string;
Wing->config->set('tenants/sso_key', $guid);

is tenantsso({})->{error}{message}, 'You need a tenant sso key.', 'request with missing tenant sso key';

is tenantsso({api_key => Data::GUID->guid_string, })->{error}{message}, 'Wrong tenant sso key', 'request with the wrong sso key';

is tenantsso({api_key => $guid, })->{error}{message}, 'You must specify a password.', 'request with no password';

is tenantsso({api_key => $guid, password => 'foo-baz-bar', })->{error}{message}, 'You must specify a username or user_id.', 'request with no user identifier of any type';

is tenantsso({api_key => $guid, password => 'foo-baz-bar', username => 'warden'})->{error}{message}, 'User not found.', 'user not found due to no username match';

is tenantsso({api_key => $guid, password => 'foo-baz-bar', user_id => Data::GUID->guid_string, })->{error}{message}, 'User not found.', 'user not found due to no user_id match';

is tenantsso({api_key => $guid, password => 'foo-baz-bar', username => 'andy', })->{error}{message}, 'Password incorrect.', 'user not found due to username/password mismatch';

is tenantsso({api_key => $guid, password => 'foo-baz-bar', user_id => $andy->id, })->{error}{message}, 'Password incorrect.', 'user not found due to user_id/password mismatch';

$result = tenantsso({api_key => $guid, password => 'Saywatanayo', user_id => $andy->id, })->{result};
cmp_deeply(
    $result,
    superhashof({
        map { $_ => $andy->$_ } qw/id username is_admin display_name real_name email/
    }),
    'Got back the right user properties for andy and not andrew via user_id'
);

$result = tenantsso({api_key => $guid, password => 'Saywatanayo', username => 'andy', })->{result};
cmp_deeply(
    $result,
    superhashof({
        map { $_ => $andy->$_ } qw/id username is_admin display_name real_name email/
    }),
    'Got back the right user properties for andy and not andrew via username'
);

done_testing();

END {
    Wing->config->delete('tenants/sso_key');
}

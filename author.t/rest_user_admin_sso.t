use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Wing;
use Wing::Rest;
use Wing::DB::ResultSet;
use Plack::Test;
use Dancer::Handler;
use HTTP::Request::Common qw(GET);
use JSON qw(decode_json);

set show_errors => 0;
set logger => 'null';
my $original_tenants = Wing->config->get('tenants');
Wing->config->delete('tenants');
require Wing::Rest::User;
Wing->config->set('tenants', $original_tenants) if defined $original_tenants;
generate_read('Company');
Wing->db->source('User')->resultset_class('Wing::DB::ResultSet');
my $admin = Wing->db->resultset('User')->create({username => 'sso-admin', email => 'sso-admin@example.invalid', admin => 1});
my $victim = Wing->db->resultset('User')->create({username => 'victim', email => 'victim-mail@example.invalid'});
$victim->encrypt_and_set_password('original')->update;
my $key = $admin->apikeys->create({name => 'sso-admin-client'});
# No grants: an admin's app token passes check_permissions without them.
my $sso = $admin->start_session({sso => 1, api_key_id => $key->id});
my $company = Wing->db->resultset('Company')->create({name => 'Admin Corp', private_info => 'staff only'});

test_psgi(Dancer::Handler->get_handler->psgi_app, sub {
    my $request = shift;
    my $call = sub {
        my ($method, $path, $session, %form) = @_;
        my $http = HTTP::Request->new($method, 'http://localhost'.$path);
        $http->uri->query_form(session_id => $session->id, %form);
        return $request->($http);
    };

    is decode_json($call->('GET', '/api/company/'.$company->id, $sso)->content)->{result}{private_info}, 'staff only',
        'describe includes admin fields for an admin app token';

    my $search = decode_json($call->('GET', '/api/user', $sso, query => 'victim-mail')->content);
    is scalar @{$search->{result}{items}}, 1, 'an admin app token can search users by email';

    is $call->('PUT', '/api/user/'.$victim->id, $sso, admin => 1, username => 'renamed')->code, 200, 'an admin app token can edit another user';
    ok $victim->get_from_storage->admin, 'the edit saved the admin flag';
    is $victim->get_from_storage->username, 'renamed', 'the edit renamed the user';

    $call->('PUT', '/api/user/'.$victim->id, $sso, md5_password => 1, password => 'planted-hash');
    is $victim->get_from_storage->password, 'planted-hash', 'an admin app token can set an md5 password';

    my $member = Wing->db->resultset('User')->create({username => 'member', email => 'member@example.invalid'});
    my $member_key = $member->apikeys->create({name => 'member-client'});
    Wing->db->resultset('APIKeyPermission')->create({user_id => $member->id, api_key_id => $member_key->id, permission => 'edit_my_account'});
    $call->('PUT', '/api/user/'.$victim->id, $member->start_session({sso => 1, api_key_id => $member_key->id}), password => 'taken-over');
    is $victim->get_from_storage->password, 'planted-hash', 'a member cannot set another user\'s password';

    is $call->('POST', '/api/user', $sso, username => 'made-by-app', email => 'made-by-app@example.invalid')->code, 200, 'an admin app token can create users';

    is $call->('DELETE', '/api/user/'.$victim->id, $sso)->code, 200, 'an admin app token can delete another user';
    ok !Wing->db->resultset('User')->find($victim->id), 'the delete removed the user';
});
done_testing();

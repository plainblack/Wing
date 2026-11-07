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
require Wing::Rest::User;
Wing->db->source('User')->resultset_class('Wing::DB::ResultSet');
my $admin = Wing->db->resultset('User')->create({username => 'sso-admin', email => 'sso-admin@example.invalid', admin => 1});
my $victim = Wing->db->resultset('User')->create({username => 'victim', email => 'victim-mail@example.invalid'});
$victim->encrypt_and_set_password('original')->update;
my $original_hash = $victim->password;
my $key = $admin->apikeys->create({name => 'sso-admin-client'});
Wing->db->resultset('APIKeyPermission')->create({user_id => $admin->id, api_key_id => $key->id, permission => $_}) for qw(view_my_account edit_my_account);
my $sso = $admin->start_session({sso => 1, api_key_id => $key->id});
my $site = $admin->start_session({sso => 0});

test_psgi(Dancer::Handler->get_handler->psgi_app, sub {
    my $request = shift;
    my $call = sub {
        my ($method, $path, $session, %form) = @_;
        my $http = HTTP::Request->new($method, 'http://localhost'.$path);
        $http->uri->query_form(session_id => $session->id, %form);
        return $request->($http);
    };

    is $call->('PUT', '/api/user/'.$victim->id, $sso, admin => 1, username => 'renamed')->code, 450, 'admin SSO cannot edit another user';
    ok !$victim->get_from_storage->admin, 'the refused edit did not make the victim an admin';
    is $victim->get_from_storage->username, 'victim', 'the refused edit did not rename the victim';

    $call->('PUT', '/api/user/'.$victim->id, $sso, md5_password => 1, password => 'planted-hash');
    is $victim->get_from_storage->password, $original_hash, 'admin SSO cannot replace another user\'s password';
    my $member = Wing->db->resultset('User')->create({username => 'member', email => 'member@example.invalid'});
    my $member_key = $member->apikeys->create({name => 'member-client'});
    Wing->db->resultset('APIKeyPermission')->create({user_id => $member->id, api_key_id => $member_key->id, permission => 'edit_my_account'});
    $call->('PUT', '/api/user/'.$victim->id, $member->start_session({sso => 1, api_key_id => $member_key->id}), password => 'taken-over');
    is $victim->get_from_storage->password, $original_hash, 'a member cannot set another user\'s password';

    is $call->('DELETE', '/api/user/'.$victim->id, $sso)->code, 450, 'admin SSO cannot delete another user';
    ok(Wing->db->resultset('User')->find($victim->id), 'the refused delete kept the victim');

    is $call->('POST', '/api/user', $sso, username => 'made-by-app', email => 'made-by-app@example.invalid', admin => 1)->code, 450, 'admin SSO cannot create users';
    ok !Wing->db->resultset('User')->search({username => 'made-by-app'})->count, 'the refused create made no user';

    my $search = decode_json($call->('GET', '/api/user', $sso, query => 'victim-mail')->content);
    is_deeply $search->{result}{items}, [], 'admin SSO cannot search users by email';

    my $found = decode_json($call->('GET', '/api/user', $site, query => 'victim-mail')->content);
    is scalar @{$found->{result}{items}}, 1, 'an admin site session can search users by email';
    is $call->('PUT', '/api/user/'.$victim->id, $site, admin => 1)->code, 200, 'an admin site session can edit another user';
    ok $victim->get_from_storage->admin, 'the site session edit saved the admin flag';
});
done_testing();

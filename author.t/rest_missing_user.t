use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Wing;
use Wing::Rest;
use Wing::Session;
use Plack::Test;
use Dancer::Handler;
use HTTP::Request::Common qw(PUT);
use JSON qw(decode_json);

set show_errors => 0;
set behind_proxy => 0;
my $owner = Wing->db->resultset('User')->new({username => 'missing-key-owner', email => 'missing-key-owner@example.invalid'});
$owner->encrypt_and_set_password('missing-password');
$owner->insert;
my $key = $owner->apikeys->create({name => 'missing-key'});

# Deleting the user row leaves its session cached, as when a user is removed while logged in.
sub deleted_user_session {
    my ($name, %options) = @_;
    my $user = Wing->db->resultset('User')->new({username => $name, email => $name.'@example.invalid'});
    $user->encrypt_and_set_password('missing-password');
    $user->insert;
    Wing->db->resultset('APIKeyPermission')->create({user_id => $user->id, api_key_id => $key->id, permission => 'edit_my_account'});
    my $session = $user->start_session({sso => $options{sso}, api_key_id => $key->id, auth_source => 'site'});
    my $id = $user->id;
    $user->delete;
    Wing->cache->remove('user-changed-'.$id);
    Wing->cache->set('user-changed-'.$id, 1) if $options{marker};
    return ($id, $session);
}

generate_crud('MissingUser', db_class_name => 'User', permissions => ['edit_my_account']);
my $app = Dancer::Handler->get_handler->psgi_app;
test_psgi $app, sub {
    my $request = shift;
    for my $sso (0, 1) {
        for my $marker (0, 1) {
            my $name = "sso=$sso marker=$marker";
            my ($id, $session) = deleted_user_session("missing-$sso-$marker", sso => $sso, marker => $marker);
            my $res = $request->(PUT 'http://localhost/api/missinguser/'.$id,
                Cookie => 'session_id='.$session->id, Content => [real_name => 'Missing user write']);
            is $res->code, 401, "$name deleted user is refused with 401" or diag $res->content;
            like decode_json($res->content)->{error}{message}, qr/^You must log in to/, "$name returns the login error";
            ok !defined Wing->cache->get($session->key), "$name session cache entry is removed";
        }
    }
};

my ($id, $session) = deleted_user_session('missing-direct');
my $loaded = Wing::Session->new(id => $session->id, db => Wing->db);
ok !defined eval { $loaded->extend }, 'extend reports the ended session' or diag $@;
ok !$loaded->has_user_id, 'missing user session clears its user id';

done_testing;

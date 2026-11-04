use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Wing;
use Wing::Web;
use Wing::Web::Chat;
use Plack::Test;
use Dancer::Handler;
use HTTP::Request::Common qw(GET);
use Crypt::PK::RSA;
use Crypt::JWT qw(decode_jwt);

set show_errors => 0;
set views => $ENV{WING_HOME}.'/var/init/views';
set engines => {template_toolkit => {start_tag => '[%', end_tag => '%]'}};
set template => 'template_toolkit';

my $rsa = Crypt::PK::RSA->new;
$rsa->generate_key(256);
# Change the config in memory only, since Config::JSON set() writes the file.
local Wing->config->config->{firebase} = {id => 'chat-firebase', database => 'chat-db', api_key => 'chat-api-key', service_email => 'chat@example.invalid', admin_key => $rsa->export_key_pem('private')};

my $user = Wing->db->resultset('User')->create({username => 'chat-owner', email => 'chat-owner@example.invalid'});
my $denied_key = $user->apikeys->create({name => 'chat-denied-key'});
my $viewer_key = $user->apikeys->create({name => 'chat-viewer-key'});
Wing->db->resultset('APIKeyPermission')->create({user_id => $user->id, api_key_id => $viewer_key->id, permission => 'view_my_account'});
my $editor_key = $user->apikeys->create({name => 'chat-editor-key'});
Wing->db->resultset('APIKeyPermission')->create({user_id => $user->id, api_key_id => $editor_key->id, permission => 'edit_my_account'});
my %session = (
    denied => $user->start_session({sso => 1, api_key_id => $denied_key->id})->id,
    viewer => $user->start_session({sso => 1, api_key_id => $viewer_key->id})->id,
    editor => $user->start_session({sso => 1, api_key_id => $editor_key->id})->id,
    site   => $user->start_session({sso => 0})->id,
);

test_psgi(Dancer::Handler->get_handler->psgi_app, sub {
    my $request = shift;
    my $anonymous = $request->(GET 'http://localhost/chat');
    is $anonymous->code, 401, 'chat requires a session';
    unlike $anonymous->content, qr/chat-api-key/, 'chat issues no credential without a session';
    for my $name (qw(denied viewer)) {
        my $response = $request->(GET 'http://localhost/chat', Cookie => 'session_id='.$session{$name});
        is $response->code, 450, "chat refuses the $name SSO session without edit_my_account";
        unlike $response->content, qr/chat-api-key/, "chat issues no credential to the $name SSO session";
    }
    my $query = $request->(GET 'http://localhost/chat?session_id='.$session{denied});
    is $query->code, 450, 'chat refuses a denied SSO session passed as a query parameter';
    for my $name (qw(editor site)) {
        my $response = $request->(GET 'http://localhost/chat', Cookie => 'session_id='.$session{$name});
        is $response->code, 200, "chat renders for the $name session";
        like $response->content, qr/chat-api-key/, "chat gives the Firebase config to the $name session";
        my ($jwt) = $response->content =~ /"jwt"\s*:\s*"([^"]+)"/;
        is eval { decode_jwt(token => $jwt, key => \$rsa->export_key_pem('public'))->{uid} }, $user->id, "chat signs a token for the $name session";
    }
});

done_testing;

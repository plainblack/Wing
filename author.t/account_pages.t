use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Wing;
use Wing::Web;
use Wing::DB::ResultSet;
use Wing::Web::Account;
use Plack::Test;
use Dancer::Handler;
use HTTP::Request::Common qw(GET);
use HTTP::Tiny;
use Test::TCP;
use FindBin;
use JSON qw(decode_json);
set show_errors => 0;
set logger => 'null';
set public => $ENV{WING_HOME}.'/public';
set views => $ENV{WING_HOME}.'/var/init/views';
set engines => {template_toolkit => {start_tag => '[%', end_tag => '%]'}};
set template => 'template_toolkit';
Wing->db->source($_)->resultset_class('Wing::DB::ResultSet') for qw(User APIKey APIKeyPermission);
my $user = Wing->db->resultset('User')->create({username => 'account-render', email => 'account-render@example.invalid', real_name => 'Account Owner'});
$user->mark_secondary_auth_verified;
my $key = $user->apikeys->create({name => 'rendered-key'});
my $session = $user->start_session({sso => 0});
test_psgi(Dancer::Handler->get_handler->psgi_app, sub {
    my $request = shift;
    my $response = $request->(GET 'http://localhost/account', Cookie => 'session_id='.$session->id);
    is $response->code, 200, 'shipped account settings render for a verified site session';
    like $response->content, qr/Account Settings/, 'account settings template rendered';
    my $keys = $request->(GET 'http://localhost/account/apikeys', Cookie => 'session_id='.$session->id);
    is $keys->code, 200, 'shipped API key list renders for a verified site session';
    like $keys->content, qr{list_api : '/api/user/} , 'key list uses the current user relationship endpoint';
});
my $api = Test::TCP->new(code => sub {
    exec $^X, "$FindBin::Bin/bin/rest-app.pl", shift, 'Wing::Rest::User', 'Wing::Rest::APIKey';
    die "Could not start the REST app: $!";
});
my $rest = HTTP::Tiny->new(default_headers => {Cookie => 'session_id='.$session->id});
my $rest_uri = 'http://127.0.0.1:'.$api->port;
# Follow the endpoints the page's Vue objects call, the way the browser would.
test_psgi(Dancer::Handler->get_handler->psgi_app, sub {
    my $request = shift;
    my @cookie = (Cookie => 'session_id='.$session->id);
    my $account = sub {
        my ($json) = $request->(GET 'http://localhost/account', @cookie)->content =~ /properties : (\{.*\}),\s*params :/s;
        return decode_json($json);
    };
    my $properties = $account->();
    is $properties->{username}, 'account-render', 'account page embeds the username';
    is $properties->{email}, 'account-render@example.invalid', 'account page embeds the email';
    is $properties->{_relationships}{self}, '/api/user/'.$user->id, 'account page saves to the user endpoint';
    my $saved = $rest->request(PUT => $rest_uri.$properties->{_relationships}{self}, {headers => {'Content-Type' => 'application/x-www-form-urlencoded'}, content => $rest->www_form_urlencode({real_name => 'Browser Updated Owner'})});
    is $saved->{status}, 200, 'saving the account page succeeds';
    is $account->()->{real_name}, 'Browser Updated Owner', 'saved real name shows after reload';
    my ($list) = $request->(GET 'http://localhost/account/apikeys', @cookie)->content =~ /list_api : '([^']+)'/;
    my $keys = decode_json($rest->get($rest_uri.$list)->{content})->{result}{items};
    is_deeply [map { [$_->{name}, $_->{edit_uri}] } @$keys],
        [['rendered-key', '/account/apikeys/'.$key->id]], 'key list shows the owner key and links to it';
});
undef $api;
done_testing;

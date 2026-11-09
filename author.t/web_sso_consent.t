use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Wing;
use Wing::Web;
use Wing::Web::Account;
use Wing::SSO;
use Plack::Test;
use Dancer::Handler;
use HTTP::Request::Common;

set show_errors => 0;
set logger => 'null';
set public => $ENV{WING_HOME}.'/public';
set views => $ENV{WING_HOME}.'/var/init/views';
set engines => {template_toolkit => {start_tag => '[%', end_tag => '%]'}};
set template => 'template_toolkit';

my $owner = Wing->db->resultset('User')->create({username => 'sso-key-owner', email => 'sso-key-owner@example.invalid'});
my $key = $owner->apikeys->create({name => 'sso-consent-client'});
my $visitor = Wing->db->resultset('User')->new({username => 'sso-visitor', email => 'sso-visitor@example.invalid'});
$visitor->encrypt_and_set_password('visitor-password');
$visitor->insert;
my $postback = 'https://client.example.invalid/back';

sub approved { Wing::SSO->new(id => $_[0], db => Wing->db)->consented }
sub grants { [sort @{Wing::SSO->new(db => Wing->db, api_key_id => $key->id, user_id => $visitor->id)->get_permissions}] }

test_psgi(Dancer::Handler->get_handler->psgi_app, sub {
    my $request = shift;
    my $cookie = 'session_id='.$visitor->start_session({sso => 0})->id;
    my $sso = sub { $request->(GET 'http://localhost/sso?api_key_id='.$key->id.'&postback_uri='.$postback.$_[0], Cookie => $cookie) };

    for my $query ('', '&permission=', '&permission=bogus') {
        my $response = $sso->($query);
        is $response->code, 302, "unapproved key with '$query' redirects";
        like $response->header('Location'), qr{^(?:http://localhost)?/sso/authorize\?sso_id=}, "unapproved key with '$query' shows the consent form";
    }
    my ($sso_id) = $sso->('&permission=bogus')->header('Location') =~ /sso_id=([^&]+)/;
    my $form = $request->(GET 'http://localhost/sso/authorize?sso_id='.$sso_id, Cookie => $cookie);
    is $form->code, 200, 'consent form renders for a request with no supported permission';
    unlike $form->content, qr/bogus/, 'consent form lists no unsupported permission';
    my $approval = $request->(POST 'http://localhost/sso/authorize', Cookie => $cookie, Content => [sso_id => $sso_id]);
    is $approval->code, 302, 'approving a request with no supported permission succeeds';
    is $approval->header('Location'), $postback.'?sso_id='.$sso_id, 'approval redirects to the postback';
    is_deeply grants(), [], 'approval grants no unsupported permission';

    my $known = Wing::SSO->new(db => Wing->db, api_key_id => $key->id, postback_uri => $postback)->store->id;
    my $login = $request->(POST 'http://localhost/login', Cookie => 'sso_id='.$known, Content => [login => 'sso-visitor', password => 'visitor-password', sso_id => $known]);
    like $login->header('Location'), qr{/sso/authorize\?sso_id=}, 'login for an unapproved key shows the consent form';
    ok !approved($known), 'login does not approve a token for a key the visitor never approved';
    my ($unapproved) = $sso->('')->header('Location') =~ /sso_id=([^&]+)/;
    ok !approved($unapproved), 'GET /sso does not approve a token for a key the visitor never approved';
    ok approved($sso_id), 'approving on the consent form approves the token';

    my ($granted) = $sso->('&permission=view_my_account')->header('Location') =~ /sso_id=([^&]+)/;
    $request->(POST 'http://localhost/sso/authorize', Cookie => $cookie, Content => [sso_id => $granted]);
    is_deeply grants(), ['view_my_account'], 'approval grants the requested permission';
    for my $query ('', '&permission=view_my_account', '&permission=bogus') {
        my ($id) = $sso->($query)->header('Location') =~ m{^\Q$postback\E\?sso_id=([^&]+)};
        ok $id, "approved key with '$query' goes straight to the postback";
        ok approved($id), "approved key with '$query' gets an approved token";
    }
    like $sso->('&permission=edit_my_account')->header('Location'), qr{/sso/authorize\?sso_id=}, 'a new permission still needs consent';
});

done_testing;

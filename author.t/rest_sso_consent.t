use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer;
use Wing;
use Wing::Rest;
use Wing::Rest::Session;
use Wing::SSO;
use Plack::Test;
use Dancer::Handler;
use HTTP::Request::Common;

set show_errors => 0;
set logger => 'null';

my $owner = Wing->db->resultset('User')->create({username => 'sso-exchange-owner', email => 'sso-exchange-owner@example.invalid'});
my $visitor = Wing->db->resultset('User')->create({username => 'sso-exchange-visitor', email => 'sso-exchange-visitor@example.invalid'});
my $key = $owner->apikeys->create({name => 'sso-exchange-client'});

test_psgi(Dancer::Handler->get_handler->psgi_app, sub {
    my $request = shift;
    my $exchange = sub { $request->(POST 'http://localhost/api/session/sso/'.$_[0]->id, Content => [private_key => $key->private_key]) };
    my $unapproved = Wing::SSO->new(db => Wing->db, api_key_id => $key->id, user_id => $visitor->id)->store;
    my $refused = $exchange->($unapproved);
    is $refused->code, 450, 'a token the user has not approved cannot be exchanged';
    like $refused->content, qr/not approved/, 'the refusal says the user has not approved the request';
    my $approved = Wing::SSO->new(db => Wing->db, api_key_id => $key->id, user_id => $visitor->id)->store->consent;
    my $response = $exchange->($approved);
    is $response->code, 200, 'an approved token can be exchanged';
    like $response->content, qr/\Q${\ $visitor->id }\E/, 'the session belongs to the approving user';
});

done_testing;

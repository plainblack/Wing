use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Wing;
use Wing::Rest::Wingman;
use Wing::DB::ResultSet;
use Plack::Test;
use Dancer::Handler;
use HTTP::Request::Common qw(GET);
use JSON qw(decode_json);

set show_errors => 0;
set logger => 'null';
my $original_tenants = Wing->config->get('tenants');
Wing->config->delete('tenants');
require Wing::Rest::Trends;
require Wing::Rest::Idea;
require Wing::Rest::NotFound;
Wing->config->set('tenants', $original_tenants) if defined $original_tenants;
Wing->db->source('TrendsReport')->resultset_class('Wing::DB::ResultSet');
my $admin = Wing->db->resultset('User')->create({username => 'rest-admin', email => 'rest-admin@example.invalid', admin => 1});
my $key = $admin->apikeys->create({name => 'rest-admin-client'});
my $sso = $admin->start_session({sso => 1, api_key_id => $key->id});
my $site = $admin->start_session({sso => 0});
my @routes = (
    ['GET', '/api/wingman/stats'], ['GET', '/api/wingman/tubes'], ['GET', '/api/wingman/tubes/wingman_test/stats'],
    ['GET', '/api/wingman/tubes/wingman_test/jobs'], ['POST', '/api/wingman/tubes/wingman_test/pause'],
    ['GET', '/api/wingman/tubes/wingman_test/jobs/buried'], ['GET', '/api/wingman/tubes/wingman_test/jobs/ready'],
    ['GET', '/api/wingman/tubes/wingman_test/jobs/delayed'], ['GET', '/api/wingman/jobs'],
    ['GET', '/api/wingman/jobs/buried'], ['GET', '/api/wingman/jobs/ready'], ['GET', '/api/wingman/jobs/delayed'],
    ['GET', '/api/wingman/jobs/1'], ['POST', '/api/wingman/jobs/1/kick'], ['DELETE', '/api/wingman/jobs/1'],
    ['POST', '/api/wingman/jobs'],
    ['GET', '/api/trends/hourly/1'], ['GET', '/api/trends/daily/1'], ['GET', '/api/trends/monthly/1'],
    ['GET', '/api/trends/yearly/1'], ['GET', '/api/trendsreport'],
    ['PUT', '/api/idea/1/lock'], ['PUT', '/api/idea/1/unlock'],
);
test_psgi(Dancer::Handler->get_handler->psgi_app, sub {
    my $request = shift;
    my $call = sub {
        my ($method, $path, $session) = @_;
        # Clear every minute bucket of the rate limit so the route count cannot trip it.
        Wing->cache->remove('rpc_count_'.$_.$session->user_id) for 0..59;
        my $http = HTTP::Request->new($method, 'http://localhost'.$path);
        $http->uri->query_form(session_id => $session->id);
        return $request->($http);
    };
    for my $permission (undef, 'view_my_account') {
        if (defined $permission) {
            Wing->db->resultset('APIKeyPermission')->create({user_id => $admin->id, api_key_id => $key->id, permission => $permission});
        }
        for my $route (@routes) {
            my $response = $call->(@$route, $sso);
            is $response->code, 450, "@$route refuses admin SSO with ".($permission || 'no permissions');
            like $response->content, qr/site session/, "@$route tells the app to use a site session";
        }
    }
    my $idea = Wing->db->resultset('Idea')->create({name => 'Keep me', description => 'An idea', user_id => $admin->id});
    my $delete = $call->('DELETE', '/api/idea/'.$idea->id, $sso);
    is $delete->code, 450, 'DELETE /api/idea refuses admin SSO';
    like $delete->content, qr/site session/, 'DELETE /api/idea tells the app to use a site session';
    ok(Wing->db->resultset('Idea')->find($idea->id), 'refused SSO delete keeps the idea');
    is $call->('DELETE', '/api/idea/'.$idea->id, $site)->code, 200, 'DELETE /api/idea accepts an admin site session';
    for my $route (['GET', '/api/wingman/stats'], ['GET', '/api/wingman/tubes'], ['GET', '/api/trendsreport']) {
        is $call->(@$route, $site)->code, 200, "@$route accepts an admin site session";
    }
    my $member = Wing->db->resultset('User')->create({username => 'rest-member', email => 'rest-member@example.invalid'});
    my $denied = $call->('GET', '/api/wingman/stats', $member->start_session({sso => 0}));
    is $denied->code, 450, 'a non-admin site session is refused';
    like $denied->content, qr/must be an admin/, 'the non-admin refusal says why';
});
done_testing();

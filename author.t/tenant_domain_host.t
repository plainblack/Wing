use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Wing;
use Wing::Rest;
use Plack::Test;
use Dancer::Handler;
use HTTP::Request::Common qw(GET);

set show_errors => 0;
set logger => 'null';
# The test config's domain has no dot, and a dot is what an unescaped domain would let any character match.
local Wing->config->config->{tenants}{domain} = 'tenants.example';

my $owner = Wing->db->resultset('User')->create({username => 'domain-owner', email => 'domain-owner@example.invalid'});
my $site = Wing->db->resultset('Site')->new({});
$site->name('Domain Site');
$site->hostname('domain-site.example.invalid');
$site->shortname('testwing_domainhost');
$site->user($owner);
$site->insert;

get '/tenant/shortname' => sub { my $tenant = site(); return $tenant ? $tenant->shortname : 'none' };

test_psgi(Dancer::Handler->psgi_app, sub {
    my $cb = shift;
    my $tenant = sub { from_json($cb->(GET 'http://'.$_[0].'/tenant/shortname')->content)->{result} };
    is $tenant->('testwing_domainhost.tenants.example'), 'testwing_domainhost',
        'a subdomain of tenants/domain resolves to the tenant with that shortname';
    is $tenant->('testwing_domainhost.tenantsXexample'), 'none',
        'a host that only matches tenants/domain with its dots as wildcards resolves to no tenant';
});
done_testing;

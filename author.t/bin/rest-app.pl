use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../lib", "$FindBin::Bin/../lib";
use Dancer ':syntax';
use Wing;
use Wing::DB::ResultSet;
# Wing's web and REST routes cannot load in one process, so tests serve REST from this one: rest-app.pl port Module...
my ($port, @modules) = @ARGV;
{
    local Wing->config->config->{tenants};
    eval "require $_; 1" or die $@ for @modules;
}
use HTTP::Server::PSGI;
use Dancer::Handler;
set logger => 'null';
set show_errors => 0;
Wing->db->source($_)->resultset_class('Wing::DB::ResultSet') for qw(User APIKey APIKeyPermission);
HTTP::Server::PSGI->new(host => '127.0.0.1', port => $port)->run(Dancer::Handler->get_handler->psgi_app);

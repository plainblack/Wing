use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../lib", "$FindBin::Bin/../lib";
use Dancer ':syntax';
use Wing;
use Wing::DB::ResultSet;
{
    local Wing->config->config->{tenants};
    require Wing::Rest::User;
    require Wing::Rest::APIKey;
}
use HTTP::Server::PSGI;
use Dancer::Handler;
set logger => 'null';
set show_errors => 0;
Wing->db->source($_)->resultset_class('Wing::DB::ResultSet') for qw(User APIKey APIKeyPermission);
HTTP::Server::PSGI->new(host => '127.0.0.1', port => $ARGV[0])->run(Dancer::Handler->get_handler->psgi_app);

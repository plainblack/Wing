use lib '/data/[% project %]/lib', '/data/Wing/lib';

use Wing::Perl;
use Wing;
use DateTime;

my $config = Wing->config;
my $db = Wing->db;

say $db->deployment_statements();



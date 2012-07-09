use lib '/data/[% project %]/lib', '/data/Wing/lib';

use Wing::Perl;
use Wing;
use DateTime;

my $config = Wing->config;
my $db = Wing->db;

foreach my $name ($db->sources) {
    say $name;
}


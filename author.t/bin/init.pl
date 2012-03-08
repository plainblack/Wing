use lib '/data/Wing/author.t/lib', '/data/Wing/lib';

use Wing::Perl;
use Wing;
use DateTime;
use Time::HiRes;

my $config = Wing->config;
my $db = Wing->db;

my $t = [Time::HiRes::tv_interval];
$db->deploy({ add_drop_table => 1 });

say "Time Elapsed: ".Time::HiRes::tv_interval($t);

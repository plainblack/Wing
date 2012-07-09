use lib '/data/[% project %]/lib', '/data/Wing/lib';

use Wing::Perl;

use Wing;
use DateTime;
use Time::HiRes;

my $config = Wing->config;
my $db = Wing->db;

my $t = [Time::HiRes::tv_interval];
$db->deploy({ add_drop_table => 1 });

say "done deploying...adding admin";

my $admin = $db->resultset('User')->new({});
$admin->username('Admin');
$admin->email('info@example.com');
$admin->admin(1);
$admin->encrypt_and_set_password('123qwe');
$admin->insert;

say "done adding admin...creating api key";

my $key = $db->resultset('APIKey')->new({});
$key->id('WEB000123456789012345678901234567890');
$key->name('[% project %]');
$key->user_id($admin->id);
$key->insert;

say "done creating api key...";


say "Time Elapsed: ".Time::HiRes::tv_interval($t);


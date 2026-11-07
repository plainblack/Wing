#!/data/apps/bin/perl

use strict;
use feature 'say';
use Config::JSON;
use Template;
use Getopt::Long;
use File::Path qw(make_path);
use YAML;

my $project = '';
my $root = '/data';
GetOptions("app=s" => \$project, "root=s" => \$root) or die "usage: $0 --app=AppName [--root=/data]\n";

die "usage: $0 --app=AppName [--root=/data]\n" unless $project;
my $home = "$root/$project";

# make folder
make_path($home.'/lib/'.$project.'/DB/Result');
make_path($home.'/etc');
make_path($home.'/bin/setup');
make_path($home.'/var');
make_path($home.'/dbicdh/_common/deploy/1');
make_path($home.'/views');
make_path($home.'/views/admin');
make_path($home.'/views/account');

# set up default configs
my $config = Config::JSON->new('/data/Wing/var/init/etc/wing.conf');
my $new_config = Config::JSON->create($home.'/etc/wing.conf');
$new_config->config($config->config);
$new_config->set('mkits', $home.'/var/mkits/');
$new_config->set('app_namespace', $project);
$new_config->set("log4perl_config", $home."/etc/log4perl.conf",);
$new_config->get( 'db' )->[ 0 ] =~ s|PROJECT|lc( $project )|e;
$new_config->write;

# set up dancer config
my $dancer_config = YAML::LoadFile('/data/Wing/var/init/config.yml');
$dancer_config->{appname} = $project;
$dancer_config->{log4perl}{config_file} = $home.'/etc/log4perl.conf';
$dancer_config->{engines}{template_toolkit}{INCLUDE_PATH} = $home.'/views';
YAML::DumpFile($home.'/config.yml', $dancer_config);

# set up needed files
my $tt = Template->new({ABSOLUTE => 1});
my $vars = {project => $project, wing_home => $ENV{WING_HOME}, };
template($tt,'lib/DB.pm', $vars, 'lib/'.$project.'/DB.pm') || die $tt->error();
template($tt,'lib/Web.pm', $vars, 'lib/'.$project.'/Web.pm') || die $tt->error();
template($tt,'lib/Rest.pm', $vars, 'lib/'.$project.'/Rest.pm') || die $tt->error();
template($tt,'lib/DB/Result/APIKey.pm', $vars, 'lib/'.$project.'/DB/Result/APIKey.pm');
template($tt,'lib/DB/Result/APIKeyPermission.pm', $vars, 'lib/'.$project.'/DB/Result/APIKeyPermission.pm');
template($tt,'lib/DB/Result/User.pm', $vars, 'lib/'.$project.'/DB/Result/User.pm');
template($tt,'lib/DB/Result/TrendsReport.pm', $vars, 'lib/'.$project.'/DB/Result/TrendsReport.pm');
template($tt,'lib/DB/Result/TrendsLog.pm', $vars, 'lib/'.$project.'/DB/Result/TrendsLog.pm');
template($tt,'lib/DB/Result/TrendsLogHourly.pm', $vars, 'lib/'.$project.'/DB/Result/TrendsLogHourly.pm');
template($tt,'lib/DB/Result/TrendsLogDaily.pm', $vars, 'lib/'.$project.'/DB/Result/TrendsLogDaily.pm');
template($tt,'lib/DB/Result/TrendsLogMonthly.pm', $vars, 'lib/'.$project.'/DB/Result/TrendsLogMonthly.pm');
template($tt,'lib/DB/Result/TrendsLogYearly.pm', $vars, 'lib/'.$project.'/DB/Result/TrendsLogYearly.pm');
template($tt,'etc/log4perl.conf', $vars);
template($tt,'etc/mime.types', $vars);
template($tt,'etc/nginx.conf', $vars);
template($tt,'bin/web.psgi', $vars);
template($tt,'bin/rest.psgi', $vars);
template($tt,'bin/setup/install_perl_modules.sh', $vars);
template($tt,'dbicdh/_common/deploy/1/install_admin.pl', $vars);

# mail kits are runtime templates, so copy them untouched
system('cp', '-R', '/data/Wing/var/init/var/mkits', $home.'/var/') == 0 or die "Could not copy the mail kits into $home/var/mkits.\n";

# set up views, using alternate template tags since they're templates
my $t_alt = Template->new({ABSOLUTE => 1, START_TAG => quotemeta('[%['), END_TAG => quotemeta(']%]')});
template($t_alt,'views/footer_include.tt', $vars);
template($t_alt,'views/header_include.tt', $vars);
template($t_alt,'views/markdowneditor_js_include.tt', $vars);
template($t_alt,'views/markdowneditor_css_include.tt', $vars);
template($t_alt,'views/wing_ui_css_requirements.tt', $vars);
template($t_alt,'views/wing_ui_js_requirements.tt', $vars);
template($t_alt,'views/error.tt', $vars);
template($t_alt,'views/admin/users.tt', $vars);
template($t_alt,'views/admin/user.tt', $vars);
template($t_alt,'views/admin/wingman.tt', $vars);
template($t_alt,'views/admin/wingman_job.tt', $vars);
template($t_alt,'views/admin/wingman_tube.tt', $vars);
template($t_alt,'views/admin/trends_reports.tt', $vars);
template($t_alt,'views/admin/manage_trends_reports.tt', $vars);
template($t_alt,'views/admin/footer_include.tt', $vars);
template($t_alt,'views/admin/header_include.tt', $vars);
template($t_alt,'views/account/apikeys.tt', $vars);
template($t_alt,'views/account/apikey.tt', $vars);
template($t_alt,'views/account/authenticate_include.tt', $vars);
template($t_alt,'views/account/authorize.tt', $vars);
template($t_alt,'views/account/footer_include.tt', $vars);
template($t_alt,'views/account/header_include.tt', $vars);
template($t_alt,'views/account/index.tt', $vars);
template($t_alt,'views/account/login_include.tt', $vars);
template($t_alt,'views/account/create_account_include.tt', $vars);
template($t_alt,'views/account/finish_facebook.tt', $vars);
template($t_alt,'views/account/login.tt', $vars);
template($t_alt,'views/account/profile.tt', $vars);
template($t_alt,'views/account/reset-password-code.tt', $vars);
template($t_alt,'views/account/reset-password.tt', $vars);
template($t_alt,'views/account/ssosuccess.tt', $vars);

# set privs
system('chmod', '755', glob("$home/bin/*")) == 0 or die "Could not make $home/bin scripts executable.\n";

# tell them what to do next
say "Be sure to export the environment variables you need for your app:\n";
say "export WING_APP=".$home;
say "export WING_CONFIG=".$home."/etc/wing.conf";
say 'database name set to ' . lc( $project );
say qq|for create database step, run command 'mysql -uroot -p -e "create database @{[ lc( $project ) ]}"'|;

sub template {
  my ($tt, $from, $vars, $to) = @_;
  $to ||= $from;
  $tt->process('/data/Wing/var/init/'.$from, $vars, $home.'/'.$to) || die $tt->error();
}

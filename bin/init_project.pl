#!/data/apps/bin/perl

use strict;
use Config::JSON;
use Template;
use Getopt::Long;
use File::Path qw(make_path);

my $project = '';
GetOptions("project=s" => \$project);

die "usage: $0 --project=ProjectName" unless $project;
$project = ucfirst $project;

# make folder
make_path('/data/'.$project.'/lib/'.$project.'/DB/Result');
make_path('/data/'.$project.'/etc');
make_path('/data/'.$project.'/bin/setup');
make_path('/data/'.$project.'/bin/util');
make_path('/data/'.$project.'/var');

# set up default configs
my $config = Config::JSON->new('/data/Wing/var/init/etc/wing.conf');
my $new_config = Config::JSON->create('/data/'.$project.'/etc/wing.conf');
$new_config->config($config->config);
$new_config->set('mkits', '/data/'.$project.'/var/mkits/');
$new_config->set('app_namespace', $project);
$new_config->set("log4perl_config", "/data/".$project."/etc/log4perl.conf",);
$new_config->write;

# set up needed files
my $tt = Template->new({ABSOLUTE => 1});
my $vars = {project => $project};
template($tt,'lib/DB.pm', $vars, 'lib/'.$project.'/DB.pm') || die $tt->error();
template($tt,'lib/DB/Result/APIKey.pm', $vars, 'lib/'.$project.'/DB/Result/APIKey.pm');
template($tt,'lib/DB/Result/APIKeyPermission.pm', $vars, 'lib/'.$project.'/DB/Result/APIKeyPermission.pm');
template($tt,'lib/DB/Result/User.pm', $vars, 'lib/'.$project.'/DB/Result/User.pm');
template($tt,'etc/log4perl.conf', $vars);
template($tt,'etc/mime.types', $vars);
template($tt,'bin/start_web.sh', $vars);
template($tt,'bin/start_rest.sh', $vars);
template($tt,'bin/restart_starman.sh', $vars);
template($tt,'bin/stop_starman.sh', $vars);
template($tt,'bin/web.psgi', $vars);
template($tt,'bin/rest.psgi', $vars);
template($tt,'bin/setup/install_perl_modules.sh', $vars);
template($tt,'bin/setup/init_db.pl', $vars);
template($tt,'bin/util/add_user.pl', $vars);
template($tt,'bin/util/generate_init_sql.pl', $vars);
template($tt,'bin/util/show_db_classes.pl', $vars);

# set privs
system('cd /data/'.$project.'/bin;chmod 755 *');

sub template {
  my ($tt, $from, $vars, $to) = @_;
  $to ||= $from;
  $tt->process('/data/Wing/var/init/'.$from, $vars, '/data/'.$project.'/'.$to) || die $tt->error();
}

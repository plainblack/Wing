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
my $tt = Template->new({INTERPOLATE => 1, EVAL_PERL => 1, ABSOLUTE => 1});
my $vars = {project => $project};
template($tt,'lib/DB.pm', $vars, 'lib/'.$project.'/DB.pm') || die $tt->error();
template($tt,'lib/DB/Result/APIKey.pm', $vars, 'lib/'.$project.'/DB/Result/APIKey.pm');
template($tt,'lib/DB/Result/APIKeyPermission.pm', $vars, 'lib/'.$project.'/DB/Result/APIKey.pm');
template($tt,'lib/DB/Result/User.pm', $vars, 'lib/'.$project.'/DB/Result/User.pm');
template($tt,'etc/log4perl.conf', $vars, 'etc/log4perl.conf');
template($tt,'etc/mime.types', $vars, 'etc/mime.types');
template($tt,'bin/start_web.sh', $vars, 'bin/start_web.sh');
template($tt,'bin/start_rest.sh', $vars, 'bin/start_rest.sh');
template($tt,'bin/restart_starman.sh', $vars, 'bin/restart_starman.sh');
template($tt,'bin/stop_starman.sh', $vars, 'bin/stop_starman.sh');
template($tt,'bin/web.psgi', $vars, 'bin/web.psgi');
template($tt,'bin/rest.psgi', $vars, 'bin/rest.psgi');
template($tt,'bin/setup/install_perl_modules.sh', $vars, 'bin/setup/install_perl_modules.sh');
template($tt,'bin/setup/init_db.pl', $vars, 'bin/setup/init_db.pl');
template($tt,'bin/util/add_user.pl', $vars, 'bin/util/add_user.pl');
template($tt,'bin/util/generate_init_sql.pl', $vars, 'bin/util/generate_init_sql.pl');
template($tt,'bin/util/show_db_classes.pl', $vars, 'bin/util/show_db_classes.pl');

# set privs
system('cd /data/'.$project.'/bin;chmod 755 *');

sub template {
  my ($tt, $from, $vars, $to) = @_;
  $tt->process('/data/Wing/var/init/'.$from, $vars, '/data/'.$project.'/'.$to) || die $tt->error();
}

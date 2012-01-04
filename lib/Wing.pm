package Wing;

use Wing::Perl;
use Config::JSON;
use CHI;
use Log::Log4perl;
use IO::File;

## singletons

# config file
die "'WING_CONFIG' environment variable has not been set" unless exists $ENV{WING_CONFIG};
die "'WING_CONFIG' environment variable does not point to a config file" unless -f $ENV{WING_CONFIG};
my $_config = Config::JSON->new($ENV{WING_CONFIG});
sub config {
    return $_config;
}

# log
die "'log4perl_config' directive missing from config file" unless $_config->get('log4perl_config');
Log::Log4perl::init($_config->get('log4perl_config'));
my $_log = Log::Log4perl->get_logger('generate_preview');
sub log {
    return $_log;
}

# DBIx::Class
die "'app_namespace' directive missing from config file" unless $_config->get('app_namespace');
die "'db' directive missing from config file" unless $_config->get('db');
my $class = $_config->get('app_namespace') . '::DB';
my $_db = $class->connect(@{$_config->get('db')});
if ($_config->get('dbic_trace')) {
    $_db->storage->debug(1);
    $_db->storage->debugfh(IO::File->new($_config->get('dbic_trace'), 'w'));
}
sub db {
    return $_db;
}

# cache
die "'cache' directive missing from config file" unless $_config->get('cache');
my $_cache = CHI->new(%{$_config->get('cache')});
sub cache {
    return $_cache;
}

1;

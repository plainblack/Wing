package Wing;

use Wing::Perl;
use Config::JSON;
use CHI;
use Ouch;
use Log::Log4perl;
use IO::File;
use Email::Sender::Simple;
use Email::MIME::Kit;
use Email::Sender::Transport::SMTP;
use DateTime::Format::RFC3339;

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
Log::Log4perl->init($_config->get('log4perl_config'));
my $_log = Log::Log4perl->get_logger;
sub log {
    return $_log;
}

# DBIx::Class
die "'app_namespace' directive missing from config file" unless $_config->get('app_namespace');
die "'db' directive missing from config file" unless $_config->get('db');
my $class = $_config->get('app_namespace') . '::DB';
eval " require $class; import $class; ";
die $@ if $@;
my $_db = $class->connect(@{$_config->get('db')});
if ($_config->get('dbic_trace')) {
    $_db->storage->debug(1);
    $_db->storage->debugfh(IO::File->new($_config->get('dbic_trace'), 'w'));
}
sub db {
    return $_db;
}

# load site DBIx::Class namespace
my $site_namespace = $_config->get('tenants/namespace');
if (defined $site_namespace) {
    my $class = $site_namespace. '::DB';
    eval " require $class; import $class; ";
}


# cache
die "'cache' directive missing from config file" unless $_config->get('cache');
my $_cache = CHI->new(%{$_config->get('cache')});
sub cache {
    return $_cache;
}

## utility methods

# format DateTime as an RFC3339 date
sub to_RFC3339 {
    my ($class, $date) = @_;
    $date ||= DateTime->now;
    return DateTime::Format::RFC3339->new->format_datetime($date);
}

# format an RFC3339 date as DateTime
sub from_RFC3339 {
    my ($class, $date) = @_;
    return DateTime::Format::RFC3339->new->parse_datetime($date);
}

# send a templated email
sub send_templated_email {
    my ($class, $template, $params, $options) = @_; 
    $params->{sitename} = $_config->get('sitename');
    my $email = Email::MIME::Kit
        ->new({ source => $_config->get('mkits').$template.'.mkit' })
        ->assemble($params);
    my $transport = Email::Sender::Transport::SMTP->new($_config->get('smtp'));
    eval {
        Email::Sender::Simple->send($email, { transport => $transport});
        if ($options->{bcc}) {
            Email::Sender::Simple->send($email, { transport => $transport, to => $options->{bcc} });
        }
    };
    if (hug) {
        $_log->fatal('Email Problem: '.bleep);
        ouch 504, 'Could not send email. Mail service down.';
    }
}


1;

package Wing;

=head1 NAME

Wing - A restful web service toolkit.

=head1 DESCRIPTION

Wing master object, providing several utility functions.

=head1 SYNOPSIS

 use Wing;

 my $db = Wing->db;
 my $cache = Wing->cache;

=head1 SUBROUTINES

These subroutines are available from this package:

=cut

use Wing::Perl;
use Config::JSON;
use CHI;
use Ouch;
use Log::Log4perl;
use IO::File;
use Email::Sender::Simple;
use Email::MIME::Kit;
use Email::Sender::Transport::SMTP;
use DateTime::Format::MySQL;

## singletons

# config file
die "'WING_CONFIG' environment variable has not been set" unless exists $ENV{WING_CONFIG};
die "'WING_CONFIG' environment variable does not point to a config file" unless -f $ENV{WING_CONFIG};
my $_config = Config::JSON->new($ENV{WING_CONFIG});

=head2 config

Return a copy of the Wing config file for this project as a L<Config::JSON> object.

=cut

sub config {
    return $_config;
}

# log
die "'log4perl_config' directive missing from config file" unless $_config->get('log4perl_config');
Log::Log4perl->init($_config->get('log4perl_config'));

=head2 log

Return a copy of the Wing logger for this project as a L<Log::Log4perl> object.

=cut

sub log {
    my $class = shift;
    my $module = shift || 'Wing';
    return Log::Log4perl->get_logger($module);
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

=head2 db

Return a copy of a database handle for this object as a L<DBIx::Class> object

=cut

sub db {
    return $_db;
}

# load site DBIx::Class namespace
my $site_namespace = $_config->get('tenants/namespace');
if (defined $site_namespace) {
    my $class = $site_namespace. '::DB';
    eval " require $class; import $class; ";
}


=head2 tenant ( shortname )

=over

=item shortname

The name of the tenant site. Example: B<name>.domain.com

=back

=cut

sub tenant {
    my ($class, $name) = @_;
    return Wing->db->resultset('Site')->search({shortname => $name},{rows => 1})->single;
}

=head2 tenant_db( shortname )

Return a database handle for a tenant database as a L<DBIx::Class> object.

=over

=item shortname

The name of the tenant site. Example: B<name>.domain.com

=back

=cut

sub tenant_db {
    my ($class, $name) = @_;
    return $class->tenant($name)->connect_to_database;
}

# cache
die "'cache' directive missing from config file" unless $_config->get('cache');
my $_cache = CHI->new(%{$_config->get('cache')});

=head2 cache

Return a copy of a cache object for this object as a L<CHI> object

=cut

sub cache {
    return $_cache;
}

## utility methods

=head2 to_mysql

Format a DateTime object as an mysql date

=cut

sub to_mysql {
    my ($class, $date) = @_;
    $date ||= DateTime->now;
    return DateTime::Format::MySQL->format_datetime($date);
}

=head2 from_mysql

Format an mysql date as DateTime

=cut

sub from_mysql {
    my ($class, $date) = @_;
    my $dt = DateTime::Format::MySQL->new->parse_datetime($date);
    $dt->set_time_zone('UTC');
    return $dt;
}

=head2 send_templated_email ($class, $template, $params, $options)

This is a class method for sending out a templated email.  It is a
light wrapper around L<Email::MIME::Kit>.  If an error
occurs during the sending of any email it will throw an exception.

If the environment variable C<WING_NO_EMAIL> is set to 1, then this method
will return without doing anything.

If the config directive C<email_override> is set to an email address, that email
address will receive all email rather than the original recipient. CC and BCC
will still go to intended targets.

=head3 $template

The name of a template to use for building the email.  This should be a directory
in the mkits directory for the project.

=head3 $params

A hashref of parameters to send to L<Email::MIME::Kit>'s assemble method, called on
a newly created object.  Please see the docs for the module for which params are
available.

=head3 $options

A hashref of options for changing the behavior of this method

=head4 bcc

If this option exists, then a copy of the email will be sent to the value of
the option.

=head4 wingman

Boolean. If this option is true the email will be sent in the background via L<Wingman> instead of immediately.

B<NOTE:> To use this feature you must have a C<wingman> section in your config file configured properly, and a live C<beanstalkd> server.

=head4 wingman_job_options

Hash reference. See L<Wingman/put> for details.

B<NOTE:> C<ttr> defaults to 60. C<priority> defaults to 1500.

=cut

sub send_templated_email {
    my ($class, $template, $params, $options) = @_;
    if ($ENV{WING_NO_EMAIL}) {
        Wing->log->info('Skipping sending email '.$template.' due to WING_NO_EMAIL environment variable.');
        return;
    }
    my $result;
    if ($options->{wingman}) {
        delete $options->{wingman};
        my $job_options = $options->{wingman_job_options} || { ttr => 60, priority => 1500 };
        delete $options->{wingman_job_options};
        unless (defined $job_options->{ttr}) {
            $job_options->{ttr} = 60;
        }
        unless (defined $job_options->{priority}) {
            $job_options->{priority} = 1500;
        }
        Wingman->new->put('SendTemplatedEmail',{
            template    => $template,
            params      => $params,
            options     => $options,
        }, $job_options);
    }
    else {
        $params->{sitename} = $_config->get('sitename');
        my $email = Email::MIME::Kit
            ->new({ source => $_config->get('mkits').$template.'.mkit' })
            ->assemble($params);
        my $transport = Email::Sender::Transport::SMTP->new($_config->get('smtp'));
        eval {
            my @send = (
                $email,
                { transport => $transport }
                );
            if ($_config->get('email_override')) {
                $send[1]->{to} = $_config->get('email_override');
            }
            $result = Email::Sender::Simple->send(@send);
            unless ($_config->get('email_override')) {
                if ($options->{bcc}) {
                    $send[1]->{to} = $options->{bcc};
                    Email::Sender::Simple->send(@send);
                }
            }
        };
        if (hug) {
            __PACKAGE__->log->fatal('Email Problem: '.bleep);
            __PACKAGE__->log->debug('Defective Email: '.$email->as_string);
            my $error = bleep;
            $error =~ s/(.*?)\s+Trace begun.*/$1/gms;
            ouch 504, 'Could not send email: '.$error;
        }
    }
    return $result;
}


1;

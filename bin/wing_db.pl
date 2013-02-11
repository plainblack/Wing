#!/usr/bin/env perl
 
BEGIN {
 die "Must set WING_HOME environment variable." unless $ENV{WING_HOME};
 die "Must set WING_APP environment variable." unless $ENV{WING_APP};
 die "Must set WING_CONFIG environment variable." unless $ENV{WING_CONFIG};
}
use lib $ENV{WING_APP}.'/lib', $ENV{WING_HOME}.'/lib';
 
use Wing;
use Wing::Perl;
use FindBin;
use Getopt::Long;
use Pod::Usage;
 
use DBIx::Class::DeploymentHandler;

my $force_overwrite = 0;
my ($upgrade, $downgrade, $prepare_install, $install, $initialize, $prepare_update, $show_classes, $show_create);
my $nuke_ok;
my $install_version;
my ($tenant, $all_tenants);
my ($info, $help, $man);

my $ok = GetOptions(
    'force_overwrite!' => \$force_overwrite,
    'down|downgrade'   => \$downgrade,
    'up|upgrade'       => \$upgrade,
    'install'          => \$install,
    'prepare_install'  => \$prepare_install,
    'ver|version=i'    => \$install_version,
    'ok'               => \$nuke_ok,
    'initialize'       => \$initialize,
    'info'             => \$info,
    'prep|prepare'     => \$prepare_update,
    'tenant:s'         => \$tenant,
    'all_tenants'      => \$all_tenants,
    'show_classes'     => \$show_classes,
    'show_create'      => \$show_create,
    'help'             => \$help,
    'man'              => \$man,
);

die "Invalid options" unless $ok;

pod2usage( verbose => 1 ) if $help;
pod2usage( verbose => 2 ) if $man;
pod2usage( msg => "Must specify an environment variable!" ) unless $ENV{WING_CONFIG} && -e $ENV{WING_CONFIG};

use Wing; 
##Keep a copy of these in case we are working with tenants.
my $master_schema      = Wing->db;
my $master_app         = $ENV{WING_APP};
my $master_schema_name = Wing->config->get('app_namespace');

##A per-tenant/db set of variables;
my $app    = $master_app;
my $schema = $master_schema;
my $schema_name = $master_schema_name;

##--tenant can be called with a tenant site
if (defined $tenant || $all_tenants) {
    if (! Wing->config->get('tenants')) {
        die "No tenants defined for this project\n";
    }
    my $tenant_namespace = Wing->config->get('tenants/namespace');
    $app = '/data/'.$tenant_namespace;
    my $lib = $app . '/lib';
    unshift @INC, $lib;
    $schema_name = $tenant_namespace;
    say "Switching from $master_schema_name to $schema_name";
}

if (defined $tenant) {
    warn "using tenant";
    my $site;
    if ($prepare_install || $prepare_update) {
        $site = Wing->db->resultset('Site')->new({});
    }
    else {
        $site = Wing->db->resultset('Site')->search({hostname => $tenant})->single;
        if (! $site) {
            die "Could not find a tenant with name $tenant\n";
        }
    }
    $schema = $site->connect_to_database;
}

if ($show_classes) {
    foreach my $name ($schema->sources) {
        say $name;
    }
}
elsif ($show_create) {
    say $schema->deployment_statements();
}
else { # schema manipulation
 
    my $code_version = eval "use ${schema_name}::DB; ${schema_name}::DB->VERSION;";
    my $install_version ||= $code_version;
 
    ##Note, install below has a separate but almost identical DH object
    my $dh = DBIx::Class::DeploymentHandler->new( {
        schema              => $schema,
        databases           => [qw/ MySQL /],
        sql_translator_args => { add_drop_table => 0 },
        script_directory    => $app."/dbicdh",
        force_overwrite     => $force_overwrite,
    });

    say "For $ENV{WING_CONFIG}...";
    if ($tenant) {
        say "\t\t tenant site = $tenant";
    }
    say "\tCurrent code version $code_version...";
    if ($dh->version_storage_is_installed) {
        say "\tCurrent database version ".$dh->database_version."...";
    }
    else {
        say "\tNo version control installed in this database.";
    }

	if ($downgrade and $all_tenants) {
        my $sites = Wing->db->resultset('Site')->search();
        while (my $site = $sites->next) {
            my $schema = $site->connect_to_database;
            my $dh = DBIx::Class::DeploymentHandler->new( {
                schema              => $schema,
                databases           => [qw/ MySQL /],
                sql_translator_args => { add_drop_table => 0 },
                script_directory    => $app."/dbicdh",
                force_overwrite     => 0,
            });
            my $db_version = $dh->database_version;
            if ($db_version > $code_version) {
                say "Downgrading ".$site->name;
                $dh->downgrade;
                say "done";
            }
            else {
                say "No downgrades required for ".$site->name.".  Code version = $code_version, database version = $db_version";
            }
	    }
	}
	elsif ($downgrade) {
	    say "Downgrading";
	    my $db_version = $dh->database_version;
	    if ($db_version > $code_version) {
	        $dh->downgrade;
	        say "done";
	    }
	    else {
	        say "No downgrades required.  Code version = $code_version, database version = $db_version";
	    }
	}
	elsif ($upgrade and $all_tenants) {
        my $sites = Wing->db->resultset('Site')->search();
        while (my $site = $sites->next) {
            my $schema = $site->connect_to_database;
            my $dh = DBIx::Class::DeploymentHandler->new( {
                schema              => $schema,
                databases           => [qw/ MySQL /],
                sql_translator_args => { add_drop_table => 0 },
                script_directory    => $app."/dbicdh",
                force_overwrite     => 0,
            });
            my $db_version = $dh->database_version;
            if ($code_version > $db_version) {
                say "Upgrading ".$site->name;
                $dh->upgrade;
                say "done";
            }
            else {
                say "No upgrades required.  Code version = $code_version, database version = $db_version";
            }
	    }
	}
	elsif ($upgrade) {
	    say "Upgrading";
	    my $db_version = $dh->database_version;
	    if ($code_version > $db_version) {
	        $dh->upgrade;
	        say "done";
	    }
	    else {
	        say "No upgrades required.  Code version = $code_version, database version = $db_version";
	    }
	}
	elsif ($prepare_install) {
        say "Preparing files to install a new database with version $install_version";
        $dh->prepare_install();
	    say "done";
	}
	elsif ($install) {
        if (!$nuke_ok) {
            die "You didn't say that it was ok to nuke your db\n";
        }
	    say "Installing a new database with version $install_version";
        #$dh->prepare_install();
        Wing->db->storage->dbh->do('drop table if exists dbix_class_deploymenthandler_versions');
	    $dh->install({ version => $install_version, });
	    say "done";
	}
	elsif ($initialize) {
	    say "Adding DeploymentHandler to your current db";
	    $dh->install_version_storage;
	    $dh->add_database_version({ version => $schema->schema_version });
	    say "done";
	}
	elsif ($prepare_update) {
	    say "Prepare upgrade information";
	    say "\tgenerating deploy script";
	    $dh->prepare_deploy;
	    if ( $code_version > 1 ) {
	        say "\tgenerating upgrade script";
            my $previous_version = $code_version - 1;
	        $dh->prepare_upgrade( {
	                from_version => $previous_version,
	                to_version   => $code_version,
	                version_set  => [ $previous_version, $code_version ],
	            } );
	     
	        say "\tgenerating downgrade script";
	        $dh->prepare_downgrade( {
	                from_version => $code_version,
	                to_version   => $previous_version,
	                version_set  => [ $code_version, $previous_version ],
	            } );
	    }
	    say "done";
	}
    elsif ($info) {
        ##Do nothing, but don't generate the message below
    }
	else {
	    say "You didn't tell me to do anything that I recognize";
	}
} 

=head1 NAME

wing_db.pl - manipulate database schema, handling installs, upgrades and downgrades

=head1 SYNOPSIS

 wing_db.pl --show_create
 wing_db.pl --show_classes

 wing_db.pl --up
 wing_db.pl --down
 wing_db.pl --prep
 wing_db.pl --install --ok

 wing_db.pl --tenant=trial --up

 wing_db.pl --help
 wing_db.pl --info

=head1 DESCRIPTION


Greetings, future victim of automatic database manipulation.  This document
describes the futile ways in which you will try to decrease your workload
via the use of this script.

Weep now, while you still can.

A few notes:

You must have a C<WING_CONFIG> environment variable set to the configuration file
for your Wing project.  If you don't, prepare for programatically generated shame.

The VERSION for the database should be kept in C<$ENV{WING_APP}/lib/$PROJECT/DB.pm> in a publicly
available scalar variable.  If you used Wing's C<wing_init_app.pl> this was done for
you automatically.

Each branch should contain ONE and ONLY ONE increase in the VERSION number.

=head1 GETTING STARTED

When initializing a new database for development, you need run an install.  This will
install the latest version.

  wing_db.pl --prepare_install
  wing_db.pl --install --ok

=head1 DESTROYING DATA

The B<prepare> command creates consistent SQL file names, and to
protect you, L<DBIx::Class::DeploymentHandler> will not overwrite files
that already exist.  When regenerating upgrade and downgrade files, you
need to tell B<wing_db> to overwrite files using the B<force_overwrite>
option.

=head1 BRANCHING AND MAKING CHANGES

First, by the waning light of your creativity, create your branch in git.

Next, increment C<$VERSION> in C<$ENV{WING_APP}/lib/$PROJECT/DB.pm> by one.  You
may commit this change.

Continue by making your database changes in the Results and ResultSets.  When you
wish to use this code, type:

  wing_db.pl --prep

this will create all the SQL and DDL changes required for the upgrade.  Then
chant

  wing_db.pl --up

and your database will be upgraded.

=head2 Feeling down

You may observe that you have made yet another mistake, or need to add more changes to the
database.  If so, then:

Decrease $VERSION in lib/$PROJECT/DB.pm

  wing_db.pl --down

Make your additional changes, fix your mistakes, again, and sob uncontrollably.
Increase C<$VERSION> in C<lib/$PROJECT/DB.pm>

  wing_db.pl --prep
  wing_db.pl --up

=head2 Fill in the blanks.

So you've created a new column, only to find that it is empty.  You would like to fix
this and since you obsess over automating database work, you may use any or all of
L<DBIx::Class::DeploymentHandler>'s methods for doing that.

Briefly, you create a new directory C<dbicdh/_common/upgrade/x-y>, which C<x> is the
previous version and <y> is the new version.  You may either place an SQL file (suffixed with .sql)
or a perl file (suffixed with .pl).  The perl module should have just an anonymous subroutine
that expects a DBIx::Class schema object as its only argument:

    sub {
        my $db = shift;
        ...
    }

=head2 The urge to merge

Finally, you may believe to have successfully completed your tasks.  You're
wrong, but you may attempt to merge your code into the master branch.

Remove all traces of automatically generated code that have been added to the dbicdh directory.

Merge your branch into the master branch.

  wing_db.pl --prepare

Add and commit the code in in the dbicdh branch.

Push your branch so that others may suffer from your codification.

=head1 Cookbook

=head2 Refactoring column data.

This usually happens when you are replacing one column with data from another.  As
past of this, you need to port over the old data, perhaps making changes to it.  Since all
the schema changes happen before the deploy scripts run, this doesn't work.

One solution to this is to add the new column(s) in one database version, and then
remove the old column(s) in another version.

=head1 OPTIONS

=over

=item B<--show-create>

This option will display the SQL used to generate the database schema from scratch. This is useful to verify that everything is being created as you want it to be.

=item B<--show-classes>

This option will display the database class names that Wing automatically loaded at startup. This can sometimes be useful when diagnosing weird problems.

=item B<--up|upgrade>

This option will upgrade your current database to the latest version in your branch.

=item B<--down|downgrade>

This option will downgrade your current database to the latest version in your branch.

=item B<--prepare_install>

You will not use this option very often.  When beginning a project, you need to run C<wing_db.pl>
once to create the files to install the database and the DBIx::Class::DeploymentHandler

=item B<--install>

Use this option to install the schema for a brand new database for development.  This option
will completely wipe out any existing database, so it requires the C<--ok> switch as well
as a safety precaution.  By default, the latest version is installed, as described in C<$PROJECT::DB::VERSION>.

=item B<--ver|version>

ONLY FOR INSTALL.  This allows you to install versions other than C<$PROJECT::DB::VERSION>.  Note, schema differences due to the code may not always allows this.

=item B<--fo|force_overwrite>

By default, DBIx::Class::DeploymentHandler will not overwrite existing files.  You can
use C<--fo> to make it do that anyway.

=item B<--prep|prepare>

This option is used to make the code to upgrade a database.
B<NEVER COMMIT THE OUTPUT OF THIS SCRIPT IN ANY BRANCH OTHER THAN MASTER.>

=item B<--initialize>

This option to prepare a database that has not yet been upgraded to use DBIx::Class::DeploymentHandler.
Projects that are newly created containing this script should not need use this option.  It's only
used to retrofit existing projects with the necessary database tables and directories for managing
schema version information.

If you don't know whether or not to use this option, then don't.

=item B<--tenant=HOSTNAME>

Some Wing projects are multi-tenanted, see L<Wing::Role::Result::Site>.  This option will allow
you to pick a particular tenant site by the hostname, and work on its database.

=item B<--info>

In case you're lost, show the current versions of the code and the database.

=item B<--help>

Shows a short summary and usage

=item B<--man>

Shows this document

=back

=head1 AUTHOR

Copyright 2012-2013 Plain Black Corporation.

=cut



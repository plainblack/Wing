package Wing::Command::Command::db;

use Wing;
use Wing::Perl;
use Wing::Command -command;
use DBIx::Class::DeploymentHandler;
use FindBin;

##Keep a copy of these in case we are working with tenants.
my $master_schema      = Wing->db;
my $master_app         = $ENV{WING_APP};
my $master_schema_name = Wing->config->get('app_namespace');

##A per-tenant/db set of variables;
my $app    = $master_app;
my $schema = $master_schema;
my $schema_name = $master_schema_name;

sub abstract { 'manipulate the database schema' }

sub usage_desc { 'Manipulate database schema, handling installs, upgrades and downgrades.' }

sub opt_spec {
    return (
      [ 'downgrade|down', 'downgrade the database to "$PROJECT::DB::VERSION"' ],
      [ 'upgrade|up', 'upgrade the database to "$PROJECT::DB::VERSION"'],
      [ 'install', 'install the schema for a brand new database'],
      [ 'prepare_update|prepare|prep', 'generate the code to upgrade a database'],
      [ 'force!', 'normally destructive functions die with a warning, this overrides that', { default => 0 } ],
      [ 'tenant:s', 'work on a particular tenant database by the hostname'],
      [ 'all_tenants', 'work on all tenant databases'],
      [ 'version|ver=i', 'allows you to install versions other than "$PROJECT::DB::VERSION"'],
      [ 'info', 'show the current versions of the code and the database'],
      [ 'show_classes', 'list the DB classes Wing loads at startup'],
      [ 'show_create', 'show the SQL that would be used to create a new database'],
      [ 'prepare_install', 'run to create files for installing the current version'],
      [ 'initialize', 'prepare a database that has not yet been upgraded to use DBIx::Class::DeploymentHandler (depricated)'],
      [ 'doom|do=s', 'execute a SQL statement on one or more databases'],
    );
}

sub validate_args {
    my ($self, $opt, $args) = @_;
    # no args allowed but options!
    $self->usage_error("No args allowed, only options.") if @$args;
}

sub execute {
    my ($self, $opt, $args) = @_;

    ##--tenant can be called with a tenant site
    if (exists $opt->{tenant} || $opt->{all_tenants}) {
        if (! Wing->config->get('tenants')) {
            die "No tenants defined for this project\n";
        }
        my $tenant_namespace = Wing->config->get('tenants/namespace');
        $app = '/data/'.$tenant_namespace;
        $schema_name = $tenant_namespace;
        say "Switching from $master_schema_name to $schema_name";
    }

    my $code_version = eval "${schema_name}::DB->VERSION;";

    ##Swap out the default Wing->db connection
    if (exists $opt->{tenant}) {
        say "Using tenant: ".$opt->{tenant};
        my $site;
        if ($opt->{prepare_install} || $opt->{prepare_update}) {
            $site = Wing->db->resultset('Site')->new({});
        }
        else {
            $site = Wing->db->resultset('Site')->search({
                -or => [ { shortname => $opt->{tenant}}, {hostname => $opt->{tenant}}]
            })->single;
            if (! $site) {
                die "Could not find a tenant with name ".$opt->{tenant};
            }
        }
        $schema = $site->connect_to_database;
    }

    if ($opt->{show_classes}) {
        foreach my $name ($schema->sources) {
            say $name;
        }
    }
    elsif ($opt->{show_create}) {
        say $schema->deployment_statements();
    }
    else { # schema manipulation

        ##Note, install below has a separate but almost identical DH object
        my $dh = DBIx::Class::DeploymentHandler->new( {
            schema              => $schema,
            databases           => [qw/ MySQL /],
            sql_translator_args => { add_drop_table => 0 },
            script_directory    => $app."/dbicdh",
            force_overwrite     => $opt->{force},
        });

        say "For $ENV{WING_CONFIG}...";
        if ($opt->{tenant}) {
            say "\t\t tenant site = ".$opt->{tenant};
        }
        say "\tCurrent code version $code_version...";
        if ($dh->version_storage_is_installed) {
            say "\tCurrent database version ".$dh->database_version."...";
        }
        else {
            say "\tNo version control installed in this database.";
        }

        if ($opt->{downgrade} and $opt->{all_tenants}) {
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
        elsif ($opt->{downgrade}) {
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
        elsif ($opt->{upgrade} and $opt->{all_tenants}) {
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
        elsif ($opt->{upgrade}) {
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
        elsif ($opt->{prepare_install}) {
            say "Preparing files to install a new database with version ".$opt->{version};
            $dh->prepare_install();
            say "done";
        }
        elsif ($opt->{install}) {
            unless ($opt->{force}) {
                die "You didn't say that it was ok to nuke your db by using --force\n";
            }
            my $install_version = $opt->{version} ? $opt->{version} : $code_version;
            say "Installing a new database with version ".$install_version;
            $schema->storage->dbh->do('drop table if exists dbix_class_deploymenthandler_versions');
            $dh->install({ version => $install_version, });
            say "done";
        }
        elsif ($opt->{initialize} and $opt->{all_tenants}) {
            say "Adding DeploymentHandler to your current db";
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
                say "Adding DeploymentHandler to ".$site->name;
                $dh->install_version_storage;
                $dh->add_database_version({ version => $schema->schema_version });
                say "done";
            }
        }
        elsif ($opt->{initialize}) {
            say "Adding DeploymentHandler to your current db";
            $dh->install_version_storage;
            $dh->add_database_version({ version => $schema->schema_version });
            say "done";
        }
        elsif ($opt->{prepare_update}) {
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

                say "\tgenerating install script";
                $dh->prepare_install();
            }
            say "done";
        }
        elsif ($opt->{doom} && $opt->{all_tenants}) {
            say "Doing $opt->{doom} to all of your sites";
            my $sites = Wing->db->resultset('Site')->search();
            while (my $site = $sites->next) {
                my $schema = $site->connect_to_database;
                $schema->storage->dbh->do($opt->{doom});
            }
            say "done";
        }
        elsif ($opt->{doom}) {
            say "Doing $opt->{doom} to your site";
            $schema->storage->dbh->do($opt->{doom});
            say "done";
        }
        elsif ($opt->{info}) {
            ##Do nothing, but don't generate the message below
        }
        else {
            say "You didn't tell me to do anything that I recognize";
        }
    }
}

1;

=head1 NAME

wing db - manipulate database schema, handling installs, upgrades and downgrades

=head1 SYNOPSIS

 wing db --show_create
 wing db --show_classes

 wing db --up
 wing db --down
 wing db --prep
 wing db --install --force

 wing db --tenant=trial --up

 wing db --info

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

  wing db --prepare_install
  wing db --install --force

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

  wing db --prep

this will create all the SQL and DDL changes required for the upgrade, and for
installing new sites with this version.  Then chant

  wing db --up

and your database will be upgraded.

=head2 Feeling down

You may observe that you have made yet another mistake, or need to add more changes to the
database.  If so, then:

Decrease $VERSION in lib/$PROJECT/DB.pm

  wing db --down

Make your additional changes, fix your mistakes, again, and sob uncontrollably.
Increase C<$VERSION> in C<lib/$PROJECT/DB.pm>

  wing db --prep
  wing db --up

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

  wing db --prepare

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

You will not use this option very often.  When beginning a project, you need to run C<wing db>
once to create the files to install the database and the DBIx::Class::DeploymentHandler

=item B<--install>

Use this option to install the schema for a brand new database for development.  This option
will completely wipe out any existing database, so it requires the C<--force> switch as well
as a safety precaution.  By default, the latest version is installed, as described in C<$PROJECT::DB::VERSION>.

=item B<--ver|version>

ONLY FOR INSTALL.  This allows you to install versions other than C<$PROJECT::DB::VERSION>.  Note, schema differences due to the code may not always allows this.

=item B<--force>

By default, DBIx::Class::DeploymentHandler will not overwrite existing files.  You can
use C<--force> to make it do that anyway.

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

=item B<--all_tenants>

Similar to L<--tenant>, this option works on all tenant databases, one by one.

=item B<--info>

In case you're lost, show the current versions of the code and the database.

=back

=head1 TODO

=over 4

=item List sites

Add a switch to list the hostnames and names of all tenant sites

=item Info on all sites

Let --info and --all_tenants work together, so we can find the status of all sites at once.

=back

=head1 AUTHOR

Copyright 2012-2013 Plain Black Corporation.

=cut

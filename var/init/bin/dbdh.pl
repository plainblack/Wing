#!/usr/bin/env perl
 
use 5.12.0;
 
use strict;
use warnings;
use FindBin;
use Getopt::Long;
use Pod::Usage;
 
use DBIx::Class::DeploymentHandler;

my $force_overwrite = 0;
my ($upgrade, $downgrade, $install, $initialize, $prepare);
my ($help, $man);

my $ok = GetOptions(
    'force_overwrite!' => \$force_overwrite,
    'down|downgrade'   => \$downgrade,
    'up|upgrade'       => \$upgrade,
    'in|install'       => \$install,
    'initialize'       => \$initialize,
    'prepare'          => \$prepare,
    'help'             => \$help,
    'man'              => \$man,
);

die "Invalid options" unless $ok;

pod2usage( verbose => 1 ) if $help;
pod2usage( verbose => 2 ) if $man;
pod2usage( msg => "Must specify an environment variable!" ) unless $ENV{WING_CONFIG} && -e $ENV{WING_CONFIG};

use Wing;  ##Controlled the WING_CONFIG
my $schema = Wing->db;

my $schema_name = Wing->config->get('app_namespace');
 
my $version = eval "${schema_name}::DB->VERSION;";
 
say "Current code version $version for $ENV{WING_CONFIG}...";
 
my $dh = DBIx::Class::DeploymentHandler->new( {
        schema              => $schema,
        databases           => [qw/ MySQL /],
        sql_translator_args => { add_drop_table => 0, },
        script_directory    => "$FindBin::Bin/../dbicdh",
        force_overwrite     => $force_overwrite,
    }
);

if ($downgrade) {
    say "Downgrading";
    my $db_version = $dh->database_version;
    if ($db_version > $version) {
        $dh->downgrade;
    }
    else {
        say "No downgrades required.  Code version = $version, database version = $db_version";
    }
}
elsif ($upgrade) {
    say "Upgrading";
    my $db_version = $dh->database_version;
    if ($version > $db_version) {
        $dh->upgrade;
    }
    else {
        say "No upgrades required.  Code version = $version, database version = $db_version";
    }
}
elsif ($install) {
    say "Installing a new database";
    $dh->install({ version => 1, });
}
elsif ($initialize) {
    say "Adding DeploymentHandler to your current db";
    $dh->install_version_storage;
    $dh->add_database_version({ version => $schema->schema_version });
}
elsif ($prepare) {
    say "Preparing SQL for new version";
    say "\tgenerating deploy script";
    $dh->prepare_deploy;
    if ( $version > 1 ) {
        say "\tgenerating upgrade script";
        $dh->prepare_upgrade( {
                from_version => $version - 1,
                to_version   => $version,
                version_set  => [ $version - 1, $version ],
            } );
     
        say "\tgenerating downgrade script";
        $dh->prepare_downgrade( {
                from_version => $version,
                to_version   => $version - 1,
                version_set  => [ $version, $version - 1 ],
            } );
    }
}
else {
    say "You didn't tell me to do anything that I recognize";
}
 
say "done";

=head1 NAME

dbdh.pl - manipulate database schema, handling installs, upgrades and downgrades

=head1 SYNOPSIS

 dbdh.pl --up
 dbdh.pl --down
 dbdh.pl --prepare
 dbdh.pl --install

 dbdh.pl --help

=head1 DESCRIPTION

Greetings, future victim of automatic database manipulation.  This document
describes the futile ways in which you will try to decrease your workload
by the use of several scripts, a few modules and some arcane incantations.
Weep now, while you still can.

A few notes:

You must have a C<WING_CONFIG> environment variable set to the configuration file
for your Wing project.  If you don't, prepare for programatically generated shame.

The VERSION for the database should be kept in C<lib/$PROJECT/DB.pm> in a publicly
available scalar variable.  If you used Wing's C<init_project.pl> this ws done for
you automatically.

Each branch should contain ONE and ONLY ONE increase in the VERSION number.

=head1 GETTING STARTED

When initializing a new database for development, you need run an install
and then an upgrade:

  dbdh.pl --install
  dbdh.pl --upgrade

=head1 BRANCHING AND MAKING CHANGES

First, by the waning light of your creativity, create your branch in git.

Next, increment C<$VERSION> in C<lib/$PROJECT/DB.pm> by one.  You
may commit this change.

Continue by making your database changes in the Results and ResultSets.  When you
wish to use this code, type:

  dbdh.pl --prepare

this will create all the SQL and DDL changes required for the upgrade.  Then
chant

  dbdh.pl --up

and your database will be upgraded.

=head2 Feeling down

You may observe that you have made yet another mistake, or need to add more changes to the
database.  If so, then:

Decrease $VERSION in lib/$PROJECT/DB.pm

  dbdh.pl --down

Make your additional changes, fix your mistakes, again, and sob uncontrollably.
Increase C<$VERSION> in C<lib/$PROJECT/DB.pm>

  dbdh.pl --prepare
  dbdh.pl --up

=head2 The urge to merge

Finally, you may believe to have successfully completed your tasks.  You're
wrong, but you may attempt to merge your code into the master branch.

Remove all traces of automatically generated code that have been added to the dbicdh directory.

Merge your branch into the master branch.

  dbdh.pl --prepare

Add and commit the code in in the dbicdh branch.

Push your branch so that others may suffer from your codification.

=head1 EDGE CASES

=head2 Replacing one column with another.

Recently in TGC we refactored Document to remove the use_for column (3 options) with two columns (is_printable
and is_downloadable).  This required two revisions.

In revision one, we added the two new columns and then went over the Documents row by row to spread
the 3 options across them.

Then, in revision two, you can safely remove the old column.

=head1 OPTIONS

=over

=item B<--up|upgrade>

This option will upgrade your current database to the latest version in your branch.

=item B<--down|downgrade>

This option will downgrade your current database to the latest version in your branch.

=item B<--in|install>

Use this option to install the schema for a brand new database for development.

=item B<--prepare>

This option is used to make the code to upgrade a database.
B<NEVER COMMIT THE OUTPUT OF THIS SCRIPT IN ANY BRANCH OTHER THAN MASTER.>

=item B<--initialize>

This option prepares a database that has not yet been setup to use DBIx::Class::DeploymentHandler.
Projects that are newly created containing this script will not need use this option.  It's only
used to retrofit existing projects with the necessary database tables and directories for managing
schema version information.

If you don't know whether or not to use this option, then don't.

=item B<--help>

Shows a short summary and usage

=item B<--man>

Shows this document

=back

=head1 AUTHOR

Copyright 2012 Plain Black Corporation.

=cut



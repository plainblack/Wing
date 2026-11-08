use strict;
use warnings;
use Test::More;
use Wing;
use DBIx::Class::DeploymentHandler;
use File::Temp qw(tempdir);
use JSON qw(encode_json decode_json);
use FindBin;

my $db = Wing->db;
my $dbh = $db->storage->dbh;

my $directory = tempdir(CLEANUP => 1);
# Extra databases are named after the test database, so the test account may create them and the runner drops them.
my ($test_database) = Wing->config->get('db')->[0] =~ /database=(\w+)/
    or die "Run this test with perl author.t/run.pl, which names its database in author.t/etc/test.conf.\n";
my ($install_database, $legacy_database) = map { "${test_database}_$_" } qw(install_check legacy_check);
sub install_config {
    my $name = shift;
    my $config = decode_json(encode_json(Wing->config->config));
    $config->{db}[0] =~ s/database=\w+/database=$name/;
    return $config;
}
sub wing_db {
    my ($config, @options) = @_;
    open my $configuration, '>', "$directory/install.json" or die $!;
    print $configuration encode_json($config);
    close $configuration;
    my $status;
    {
        local $ENV{WING_CONFIG} = "$directory/install.json";
        open my $saved_stdout, '>&', \*STDOUT or die $!;
        open my $saved_stderr, '>&', \*STDERR or die $!;
        open STDOUT, '>', "$directory/install.log" or die $!;
        open STDERR, '>&', \*STDOUT or die $!;
        $status = system($^X, "$FindBin::Bin/../bin/wing", 'db', @options);
        open STDOUT, '>&', $saved_stdout or die $!;
        open STDERR, '>&', $saved_stderr or die $!;
    }
    open my $output, '<', "$directory/install.log" or die $!;
    my $command_output = do { local $/; <$output> };
    like $command_output, qr/Current code version 7/, "wing db @options output is captured for diagnostics";
    is $status, 0, "documented wing db @options succeeds";
    if ($status) {
        diag $command_output;
        BAIL_OUT('The migration command failed; dependent database checks cannot run.');
    }
}

$dbh->do("CREATE DATABASE $install_database");
my $fresh_config = install_config($install_database);
wing_db($fresh_config, '--install', '--force');
my $installed = TestWing::DB->connect(@{$fresh_config->{db}});
my $installed_dbh = $installed->storage->dbh;
my $dh = DBIx::Class::DeploymentHandler->new({schema => $installed, script_directory => "$ENV{WING_APP}/dbicdh"});
is $dh->database_version, 7, 'fresh install records version 7';
my $columns = $installed_dbh->selectcol_arrayref(q{
    SELECT COLLATION_NAME FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND (TABLE_NAME = 'users' AND COLUMN_NAME = 'id'
        OR TABLE_NAME = 'api_key' AND COLUMN_NAME = 'user_id')
});
is scalar(@$columns), 2, 'both sides of the API key user relationship exist';
is $columns->[0], $columns->[1], 'the referencing and referenced user columns have matching collations';
my ($mode, $server_mode, $foreign_keys) = $installed_dbh->selectrow_array('SELECT @@SESSION.sql_mode, @@GLOBAL.sql_mode, @@foreign_key_checks');
is $mode, $server_mode, 'the install keeps the server SQL mode';
is $foreign_keys, 1, 'foreign keys remain enabled after installation';
my $user = $installed->resultset('User')->create({username => 'installed-owner', email => 'installed-owner@example.invalid'});
my $key = $user->apikeys->create({name => 'installed-key'});
is $key->user->id, $user->id, 'the installed schema persists a valid user and related API key';
{
    local $installed_dbh->{PrintError} = 0;
    eval { $installed_dbh->do(q{
        INSERT INTO api_key (id, date_created, date_updated, name, user_id)
        VALUES ('orphan-key', NOW(), NOW(), 'orphan-key', 'missing-user')
    }) };
    is $installed_dbh->err, 1452, 'the installed foreign key rejects an orphan API key';
}

# Historical installs inherited this database default; the fresh-install test above uses native defaults.
$dbh->do("CREATE DATABASE $legacy_database CHARACTER SET utf8 COLLATE utf8_unicode_ci");
my $legacy_config = install_config($legacy_database);
wing_db($legacy_config, '--install', '--force', '--version', '5');
my $legacy = TestWing::DB->connect(@{$legacy_config->{db}});
my $legacy_dbh = $legacy->storage->dbh;
$legacy_dbh->do(q{INSERT INTO companies (id, date_created, date_updated, name, private_info)
    VALUES ('retained-company', NOW(), NOW(), 'Retained Company', 'Retained note')});
wing_db($legacy_config, '--upgrade');
my $legacy_dh = DBIx::Class::DeploymentHandler->new({schema => $legacy, script_directory => "$ENV{WING_APP}/dbicdh"});
is $legacy_dh->database_version, 7, 'the generated upgrade advances a historical version-5 database';
my $upgraded_user = $legacy->resultset('User')->create({username => 'upgraded-owner', email => 'upgraded-owner@example.invalid'});
is $upgraded_user->no_email, 0, 'the upgraded schema supports current User columns';
is $legacy->resultset('Company')->find('retained-company')->private_info, 'Retained note', 'upgrade preserves existing company data';
wing_db($legacy_config, '--downgrade', '--version', '5');
is $legacy_dh->database_version, 5, 'the generated downgrade returns the fixture to version 5';
is $legacy_dbh->selectrow_array(q{SELECT private_info FROM companies WHERE id = 'retained-company'}),
    'Retained note', 'downgrade preserves data in historical columns';
wing_db($legacy_config, '--upgrade');
is $legacy_dh->database_version, 7, 'the historical fixture can be upgraded again';

done_testing;

use strict;
use warnings;
use Test::More;
use Wing;
use DBIx::Class::DeploymentHandler;
use File::Temp qw(tempdir);
use File::Basename qw(dirname);
use Cwd qw(realpath);
use JSON qw(encode_json decode_json);
use FindBin;

my $db = Wing->db;
my $dbh = $db->storage->dbh;
my ($datadir, $socket, $private) = $dbh->selectrow_array('SELECT @@datadir, @@socket, @@skip_networking');
my $root = dirname($ENV{WING_CONFIG});
die "Run this test with bin/agent-tests.py and its disposable MySQL server.\n"
    unless $root =~ m{^/tmp/wing-check-[^/]+$} && $private
        && realpath($datadir) eq realpath("$root/db") && $socket eq "$root/mysql.sock";

my $directory = tempdir(CLEANUP => 1);
sub install_config {
    my $name = shift;
    my $config = decode_json(encode_json(Wing->config->config));
    $config->{db}[0] =~ s/database=wing_check;/database=$name;/
        or die "The isolated runner database name was not recognized.\n";
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
        open local *STDOUT, '>', "$directory/install.log" or die $!;
        open local *STDERR, '>&', \*STDOUT or die $!;
        $status = system($^X, "$FindBin::Bin/../bin/wing", 'db', @options);
    }
    is $status, 0, "documented wing db @options succeeds";
    if ($status) {
        open my $output, '<', "$directory/install.log" or die $!;
        diag do { local $/; <$output> };
        BAIL_OUT('The migration command failed; dependent database checks cannot run.');
    }
}

$dbh->do('CREATE DATABASE wing_install_check');
my $fresh_config = install_config('wing_install_check');
wing_db($fresh_config, '--install', '--force');
my $installed = TestWing::DB->connect(@{$fresh_config->{db}});
my $installed_dbh = $installed->storage->dbh;
my $dh = DBIx::Class::DeploymentHandler->new({schema => $installed, script_directory => "$ENV{WING_APP}/dbicdh"});
is $dh->database_version, 6, 'fresh install records version 6';
my $columns = $installed_dbh->selectcol_arrayref(q{
    SELECT COLLATION_NAME FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND (TABLE_NAME = 'users' AND COLUMN_NAME = 'id'
        OR TABLE_NAME = 'api_key' AND COLUMN_NAME = 'user_id')
});
is scalar(@$columns), 2, 'both sides of the API key user relationship exist';
is $columns->[0], $columns->[1], 'the referencing and referenced user columns have matching collations';
my ($strict, $foreign_keys) = $installed_dbh->selectrow_array('SELECT @@sql_mode, @@foreign_key_checks');
like $strict, qr/STRICT_TRANS_TABLES/, 'the install retains native strict SQL mode';
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
$dbh->do('CREATE DATABASE wing_legacy_check CHARACTER SET utf8 COLLATE utf8_unicode_ci');
my $legacy_config = install_config('wing_legacy_check');
wing_db($legacy_config, '--install', '--force', '--version', '5');
my $legacy = TestWing::DB->connect(@{$legacy_config->{db}});
my $legacy_dbh = $legacy->storage->dbh;
$legacy_dbh->do(q{INSERT INTO companies (id, date_created, date_updated, name, private_info)
    VALUES ('retained-company', NOW(), NOW(), 'Retained Company', 'Retained note')});
wing_db($legacy_config, '--upgrade');
my $legacy_dh = DBIx::Class::DeploymentHandler->new({schema => $legacy, script_directory => "$ENV{WING_APP}/dbicdh"});
is $legacy_dh->database_version, 6, 'the generated upgrade advances a historical version-5 database';
my $upgraded_user = $legacy->resultset('User')->create({username => 'upgraded-owner', email => 'upgraded-owner@example.invalid'});
is $upgraded_user->no_email, 0, 'the upgraded schema supports current User columns';
is $legacy->resultset('Company')->find('retained-company')->private_info, 'Retained note', 'upgrade preserves existing company data';
wing_db($legacy_config, '--downgrade', '--version', '5');
is $legacy_dh->database_version, 5, 'the generated downgrade returns the fixture to version 5';
is $legacy_dbh->selectrow_array(q{SELECT private_info FROM companies WHERE id = 'retained-company'}),
    'Retained note', 'downgrade preserves data in historical columns';
wing_db($legacy_config, '--upgrade');
is $legacy_dh->database_version, 6, 'the historical fixture can be upgraded again';

done_testing;

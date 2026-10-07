use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/lib";
use Test::More;
use DBI;
use File::Temp qw(tempdir);
use IPC::Open3;
use JSON::PP;
use SQL::Translator;

plan skip_all => 'Set WING_TEST_MYSQL_DSN and WING_TEST_MYSQL_DATADIR for an isolated deployment test'
    unless $ENV{WING_TEST_MYSQL_DSN} && $ENV{WING_TEST_MYSQL_DATADIR};

my $admin = DBI->connect($ENV{WING_TEST_MYSQL_DSN}, $ENV{WING_TEST_MYSQL_USER} // 'root', $ENV{WING_TEST_MYSQL_PASSWORD} // '', {
    RaiseError => 1, PrintError => 0, mysql_enable_utf8mb4 => 1,
});
my ($data, $networking, $mode) = $admin->selectrow_array('SELECT @@datadir,@@skip_networking,@@SESSION.sql_mode');
my $expected = $ENV{WING_TEST_MYSQL_DATADIR};
$expected .= '/' unless $expected =~ m{/$};
BAIL_OUT('Deployment tests require the explicitly named isolated datadir with networking disabled')
    unless $data eq $expected && $networking == 1;

my $database = 'wing_dh_test_'.$$;
my $app = tempdir('wing-deployment-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my ($created, $error);

sub run_wing {
    my (@options) = @_;
    my $pid = open3(undef, my $output, undef, $^X, "$FindBin::Bin/../bin/wing", 'db', @options);
    my $text = do { local $/; <$output> };
    waitpid($pid, 0);
    return ($? >> 8, $text);
}

eval {
    $admin->do("CREATE DATABASE `$database` CHARACTER SET utf8 COLLATE utf8_unicode_ci");
    $created = 1;
    is(($admin->selectrow_array('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = ?', undef, $database))[0], 0,
        'CLI install fixture is a newly created empty database');
    open my $log, '>', "$app/log4perl.conf" or die $!;
    print {$log} "log4perl.rootLogger=ERROR, Screen\nlog4perl.appender.Screen=Log::Log4perl::Appender::Screen\nlog4perl.appender.Screen.stderr=1\nlog4perl.appender.Screen.layout=Log::Log4perl::Layout::SimpleLayout\n";
    close $log or die $!;
    my $dsn = $ENV{WING_TEST_MYSQL_DSN}.";database=$database";
    my $config = {
        app_namespace => 'WingTextDefaults',
        db => [$dsn, $ENV{WING_TEST_MYSQL_USER} // 'root', $ENV{WING_TEST_MYSQL_PASSWORD} // '', {mysql_enable_utf8mb4 => 1}],
        log4perl_config => "$app/log4perl.conf", cache => {driver => 'Memory'},
    };
    my $old_umask = umask 0077;
    open my $file, '>', "$app/test.conf" or die $!;
    print {$file} JSON::PP->new->encode($config);
    close $file or die $!;
    umask $old_umask;

    local $ENV{WING_HOME} = "$FindBin::Bin/..";
    local $ENV{WING_APP} = $app;
    local $ENV{WING_CONFIG} = "$app/test.conf";
    local $ENV{PERL5LIB} = "$FindBin::Bin/../lib:$FindBin::Bin/lib";
    my ($prepared, $prepare_output) = run_wing('--prepare_install');
    is($prepared, 0, 'actual Wing CLI prepare_install succeeds');
    die $prepare_output if $prepared;
    my $sql_path = "$app/dbicdh/MySQL/deploy/1/001-auto.sql";
    my $yaml_path = "$app/dbicdh/_source/deploy/1/001-auto.yml";
    ok(-f $sql_path, 'CLI writes deployment SQL only under the scratch app');
    ok(-f $yaml_path, 'CLI writes the intermediate YAML schema');
    open my $sql_file, '<', $sql_path or die $!;
    my $sql = do { local $/; <$sql_file> };
    close $sql_file;
    like($sql, qr/`description`[^\n]*DEFAULT \(''\)/, 'DH YAML-to-MySQL path emits the text expression default');
    open my $yaml_file, '<', $yaml_path or die $!;
    my $yaml = do { local $/; <$yaml_file> };
    close $yaml_file;
    my $translator = SQL::Translator->new(parser => 'YAML', producer => 'YAML', data => $yaml);
    $translator->translate or die $translator->error;
    is($translator->schema->get_table('wing_text_defaults')->get_field('description')->default_value, '',
        'intermediate YAML retains the portable literal default');

    my $connection = DBI->connect($dsn, $config->{db}[1], $config->{db}[2], {RaiseError => 1, PrintError => 0});
    is(($connection->selectrow_array('SELECT DATABASE()'))[0], $database, 'CLI config selects only the disposable database');
    is(($connection->selectrow_array('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = ?', undef, $database))[0], 0,
        'disposable database is still empty immediately before the required CLI safety flag');
    $connection->disconnect;
    my ($installed, $install_output) = run_wing('--install', '--force');
    is($installed, 0, 'actual Wing CLI installs its prepared schema into the empty fixture');
    die $install_output if $installed;
    $admin->do("USE `$database`");
    $admin->do(q{INSERT INTO wing_text_defaults (id, date_created, date_updated) VALUES ('dh-default-check', NOW(), NOW())});
    my $row = $admin->selectrow_hashref(q{SELECT * FROM wing_text_defaults WHERE id = 'dh-default-check'});
    is($row->{description}, '', 'CLI-installed text default supplies an empty string');
    is($row->{description_html}, '', 'CLI-installed HTML default supplies an empty string');
    is($row->{custom}, "writer's\\note", 'CLI-installed quoted default keeps its original value');
    is(($admin->selectrow_array('SELECT @@SESSION.sql_mode'))[0], $mode, 'CLI pipeline leaves SQL mode unchanged');
    1;
} or $error = $@;

$admin->do("DROP DATABASE `$database`") if $created;
is(($admin->selectrow_array('SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name = ?', undef, $database))[0], 0,
    'CLI fixture database is removed after success or failure');
$admin->disconnect;
if ($error) {
    fail('complete public Wing prepare/install pipeline succeeds');
    diag($error);
}
done_testing;

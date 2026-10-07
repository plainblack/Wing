use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/lib";
use Test::More;
use SQL::Translator;
use DBI;

use WingTextDefaults::DB;

my $schema = WingTextDefaults::DB->clone;
my $source = $schema->source('DefaultFixture');
is($source->column_info('description')->{default_value}, '', 'DBIC retains the empty-string default');
is($source->column_info('custom')->{data_type}, 'text', 'Wing field retains its declared data type');
is($source->column_info('custom')->{is_nullable}, 1, 'Wing field retains its declared nullability');
is($source->column_info('custom')->{default_value}, "writer's\\note", 'Wing field retains its declared default');
is_deeply($source->column_info('custom')->{extra}, { mysql_charset => 'utf8mb4' }, 'Wing field retains its declared extras');
is($WingTextDefaults::DB::Result::DefaultFixture::custom_dbic->{default_value}, "writer's\\note", 'caller definition is unchanged');

sub translate_schema {
    my ($producer, $version) = @_;
    my $translator = SQL::Translator->new(
        parser => 'SQL::Translator::Parser::DBIx::Class',
        producer => $producer,
        data => $schema,
        quote_identifiers => 1,
        no_comments => 1,
        producer_args => defined $version ? { mysql_version => $version } : {},
    );
    my @statements = $translator->translate;
    die $translator->error unless @statements;
    return ($translator, @statements);
}

my ($mysql, @mysql_sql) = translate_schema('MySQL', '8.4.7');
my $mysql_sql = join(";\n", @mysql_sql);
for my $field (qw(description description_html empty_tinytext empty_text empty_mediumtext empty_longtext empty_tinyblob empty_blob empty_mediumblob empty_longblob)) {
    like($mysql_sql, qr/`\Q$field\E`[^\n]*DEFAULT \(''\)/, "$field uses a MySQL expression default");
}
like($mysql_sql, qr/`custom`[^\n]*DEFAULT \('writer''s\\\\note'\)/, 'caller default is quoted as a MySQL expression');
like($mysql_sql, qr/`zero`[^\n]*DEFAULT \('0'\)/, 'text zero remains a string default');
like($mysql_sql, qr/`literal_null`[^\n]*DEFAULT NULL/, 'SQL NULL semantics are preserved');
like($mysql_sql, qr/`expression`[^\n]*DEFAULT \('ready'\)/, 'explicit SQL expression is preserved');
like($mysql_sql, qr/`varchar_default`[^\n]*DEFAULT ''(?:,|\n)/, 'varchar default is unchanged');
like($mysql_sql, qr/`integer_default`[^\n]*DEFAULT 0(?:,|\n)/, 'integer default is unchanged');
for my $field (qw(undefined_default no_default)) {
    unlike($mysql_sql, qr/`\Q$field\E`[^\n]*DEFAULT/, "$field gains no default");
}
is($source->column_info('description')->{default_value}, '', 'translation does not mutate DBIC default metadata');
is($source->column_info('custom')->{default_value}, "writer's\\note", 'translation does not mutate caller defaults');
my $row = $schema->resultset('DefaultFixture')->new({});
is($row->description, '', 'new Wing objects still initialize text to an empty string');
is($row->description_html, '', 'new Wing objects still initialize filtered HTML to an empty string');

my ($sqlite, @sqlite_sql) = translate_schema('SQLite');
like(join(";\n", @sqlite_sql), qr/description[^\n]*DEFAULT ''/, 'non-MySQL producer retains its literal default');
is($sqlite->schema->get_table('wing_text_defaults')->get_field('description')->default_value, '', 'non-MySQL translated metadata is unchanged');

for my $version (undef, '5.7.44', '8.0.12') {
    my ($translator, @sql) = translate_schema('MySQL', $version);
    like(join(";\n", @sql), qr/`description`[^\n]*DEFAULT ''(?:,|\n)/,
        'older or unspecified MySQL target keeps its literal default: '.($version // 'unspecified'));
}
for my $version ('8.0.13', '8.0.33', '8.4.7', '8.000013') {
    my ($translator, @sql) = translate_schema('MySQL', $version);
    like(join(";\n", @sql), qr/`description`[^\n]*DEFAULT \(''\)/,
        "MySQL $version uses expression defaults");
}

subtest 'generated schema installs with original defaults on MySQL' => sub {
    plan skip_all => 'Set WING_TEST_MYSQL_DSN for an isolated MySQL integration test'
        unless $ENV{WING_TEST_MYSQL_DSN};
    my $admin = DBI->connect($ENV{WING_TEST_MYSQL_DSN}, $ENV{WING_TEST_MYSQL_USER} // 'root', $ENV{WING_TEST_MYSQL_PASSWORD} // '', {
        RaiseError => 1, PrintError => 0, mysql_enable_utf8mb4 => 1,
    });
    my ($mode) = $admin->selectrow_array('SELECT @@SESSION.sql_mode');
    my $database = 'wing_text_defaults_test_'.$$;
    my ($created, $installed, $error);
    eval {
        $admin->do("CREATE DATABASE `$database` CHARACTER SET utf8mb4");
        $created = 1;
        $admin->do("USE `$database`");
        $admin->do($_) for grep { /^CREATE TABLE\b/ } @mysql_sql;
        $installed = 1;
        $admin->do(q{INSERT INTO wing_text_defaults (id, date_created, date_updated) VALUES ('default-check', NOW(), NOW())});
        my $values = $admin->selectrow_hashref(q{SELECT * FROM wing_text_defaults WHERE id = 'default-check'});
        for my $field (qw(description description_html empty_tinytext empty_text empty_mediumtext empty_longtext empty_tinyblob empty_blob empty_mediumblob empty_longblob)) {
            is($values->{$field}, '', "$field defaults to the empty string in MySQL");
        }
        is($values->{custom}, "writer's\\note", 'MySQL preserves apostrophes and backslashes in caller defaults');
        is($values->{zero}, '0', 'MySQL preserves text zero');
        is($values->{expression}, 'ready', 'MySQL evaluates the supplied SQL expression');
        ok(!defined $values->{literal_null}, 'MySQL retains SQL NULL semantics');
        ok(!defined $values->{no_default}, 'nullable field without default remains NULL');
        1;
    } or $error = $@;
    ok($installed && !$error, 'unmodified generated DDL installs and accepts omitted defaulted columns');
    diag($error) if $error;
    is(($admin->selectrow_array('SELECT @@SESSION.sql_mode'))[0], $mode, 'SQL mode remains unchanged');
    $admin->do("DROP DATABASE `$database`") if $created;
    is(($admin->selectrow_array('SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name = ?', undef, $database))[0], 0, 'disposable schema is removed');
    $admin->disconnect;
    done_testing;
};

done_testing;

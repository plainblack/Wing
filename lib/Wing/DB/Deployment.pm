package Wing::DB::Deployment;

use Wing::Perl;
use DBI::Const::GetInfoType;
use SQL::Translator::Utils qw(parse_mysql_version);

sub sql_translator_args {
    my ($schema) = @_;
    my $version = $schema->storage->dbh->get_info($GetInfoType{SQL_DBMS_VER});
    die "Cannot determine the MySQL server version for schema deployment.\n"
        unless defined $version && $version =~ /\A(\d+)\.(\d+)\.(\d+)/;
    my $target = join '.', map { 0 + $_ } ($1, $2, $3);
    return {
        add_drop_table => 0,
        producer_args => { mysql_version => $target },
        filters => ['Wing::DB::Deployment'],
    };
}

sub filter {
    my ($schema) = @_;
    normalize_table_defaults($_) foreach $schema->get_tables;
}

sub normalize_table_defaults {
    my ($table) = @_;
    my $translator = $table->schema && $table->schema->translator;
    return unless $translator && $translator->producer_type =~ /\A(?:SQL::Translator::Producer::)?MySQL\z/;
    my $target = $translator->producer_args->{mysql_version};
    return unless defined $target
        && parse_mysql_version($target, 'perl') >= parse_mysql_version('8.0.13', 'perl');
    foreach my $field ($table->get_fields) {
        next unless $field->data_type =~ /\A(?:tiny|medium|long)?(?:text|blob)\z/i;
        my $default = $field->default_value;
        next unless defined $default && !ref $default && lc($default) ne 'null';
        $default =~ s/([\\'])/$1$1/g;
        my $expression = "('$default')";
        $field->default_value(\$expression);
    }
}

1;

=head1 NAME

Wing::DB::Deployment - SQL translation options for fresh Wing schema installs.

=head1 DESCRIPTION

C<sql_translator_args($schema)> obtains the connected MySQL server version
through DBI and registers this module as a SQL::Translator filter. The filter
runs after either DBIx::Class or YAML parsing, so DeploymentHandler's portable
YAML schema keeps its literal defaults while generated MySQL SQL uses the
syntax supported by the target server for C<prepare_install> and C<install>.
Upgrade diff generation retains its existing behavior.

For MySQL 8.0.13 or newer, text and blob literal defaults are emitted as
parenthesized expressions. Explicit SQL expressions, SQL NULL, other data
types, non-MySQL producers, and older or unspecified MySQL targets retain their
existing defaults. DBIx::Class column metadata is never changed.

=cut

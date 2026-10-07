package WingTextDefaults::DB::Result::DefaultFixture;

use Moose;
extends 'Wing::DB::Result';
with 'Wing::Role::Result::WebFilteredField';

our $custom_dbic = {
    data_type => 'text', is_nullable => 1,
    default_value => "writer's\\note",
    extra => { mysql_charset => 'utf8mb4' },
};
__PACKAGE__->wing_webfiltered_field(description => { view => 'public' });
__PACKAGE__->wing_field(custom => { dbic => $custom_dbic, view => 'private' });
for my $type (qw(tinytext text mediumtext longtext tinyblob blob mediumblob longblob)) {
    __PACKAGE__->wing_field("empty_$type" => {
        dbic => { data_type => $type, is_nullable => 0, default_value => '' },
    });
}
__PACKAGE__->wing_fields(
    zero => { dbic => { data_type => 'text', is_nullable => 0, default_value => 0 } },
    literal_null => { dbic => { data_type => 'text', is_nullable => 1, default_value => 'NULL' } },
    undefined_default => { dbic => { data_type => 'blob', is_nullable => 1, default_value => undef } },
    no_default => { dbic => { data_type => 'mediumtext', is_nullable => 1 } },
    expression => { dbic => { data_type => 'text', is_nullable => 0, default_value => \q{('ready')} } },
    varchar_default => { dbic => { data_type => 'varchar', size => 30, is_nullable => 0, default_value => '' } },
    integer_default => { dbic => { data_type => 'int', is_nullable => 0, default_value => 0 } },
);
__PACKAGE__->wing_finalize_class(table_name => 'wing_text_defaults');

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

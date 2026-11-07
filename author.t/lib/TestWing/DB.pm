package TestWing::DB;

use Moose;
use utf8;
no warnings qw(uninitialized);
extends qw/DBIx::Class::Schema/;

our $VERSION = 6;

__PACKAGE__->load_namespaces(
    default_resultset_class => '+Wing::DB::ResultSet',
);

no Moose;
__PACKAGE__->meta->make_immutable;

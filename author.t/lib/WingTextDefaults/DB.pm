package WingTextDefaults::DB;

use Moose;
extends 'DBIx::Class::Schema';
our $VERSION = 1;
__PACKAGE__->load_namespaces;
no Moose;
__PACKAGE__->meta->make_immutable;
1;

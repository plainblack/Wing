package [% project %]::DB;

use Moose;
use utf8;
no warnings qw(uninitialized);
extends qw/DBIx::Class::Schema/;

our $VERSION = 1;

__PACKAGE__->load_namespaces();

no Moose;
__PACKAGE__->meta->make_immutable;

package Wing::DB::ResultSet;

use Moose;
extends 'DBIx::Class::ResultSet';

sub BUILDARGS { $_[2] }

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);

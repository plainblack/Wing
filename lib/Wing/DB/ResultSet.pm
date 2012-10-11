package Wing::DB::ResultSet;

use Moose;
extends 'DBIx::Class::ResultSet';

=head1 NAME

Wing::DB::ResultSet - A base class for result sets.

=head1 SYNOPSIS

with 'DBIx::Class::ResultSet';

=head1 DESCRIPTION

Right now this class doesn't do much. In the future we will add some base functionality.


=cut

sub BUILDARGS { $_[2] }

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);

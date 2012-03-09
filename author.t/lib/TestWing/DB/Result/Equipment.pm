package TestWing::DB::Result::Equipment;

use Moose;
use Wing::Perl;
extends 'Wing::DB::Result';
with 'Wing::Role::Result::Field';
with 'Wing::Role::Result::Parent';

__PACKAGE__->wing_fields(
    name                          => {
        dbic                => { data_type => 'varchar', size => 60, is_nullable => 0 },
        view                => 'public',
        edit                => 'required',
    },
);

__PACKAGE__->wing_parent(
    employee    => {
        view            => 'public',
        edit            => 'required',
        related_class   => 'TestWing::DB::Result::Employee',
        related_id      => 'employee_id',
    }
);

__PACKAGE__->wing_finalize_class( table_name => 'equipment');


no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);

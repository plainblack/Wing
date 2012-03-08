package TestWing::DB::Result::Employee;

use Moose;
use Wing::Perl;
extends 'Wing::DB::Result';
with 'Wing::Role::Result::Field';
with 'Wing::Role::Result::Parent';
with 'Wing::Role::Result::Child';

__PACKAGE__->wing_fields(
    name                          => {
        dbic                => { data_type => 'varchar', size => 60, is_nullable => 0 },
        view                => 'public',
        edit                => 'required',
    },
    title                          => {
        dbic                => { data_type => 'varchar', size => 30, is_nullable => 1 },
        view                => 'public',
        edit                => 'admin',
    },
    salary                          => {
        dbic                => { data_type => 'int', is_nullable => 1 },
        view                => 'private',
        edit                => 'admin',
    },
);

__PACKAGE__->wing_parent(
    company    => {
        view            => 'public',
        edit            => 'postable',
        related_class   => 'TestWing::DB::Result::Company',
    }
);

__PACKAGE__->wing_child(
    equipment    => {
        view            => 'private',
        related_class   => 'TestWing::DB::Result::Equipment',
        related_id      => 'employee_id',
    }
);

__PACKAGE__->wing_finalize_class('employees');


no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);

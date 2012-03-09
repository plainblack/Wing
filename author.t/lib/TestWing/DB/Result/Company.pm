package TestWing::DB::Result::Company;

use Moose;
use Wing::Perl;
extends 'Wing::DB::Result';
with 'Wing::Role::Result::Field';
with 'Wing::Role::Result::Child';

__PACKAGE__->wing_fields(
    name                          => {
        dbic                => { data_type => 'varchar', size => 60, is_nullable => 0 },
        view                => 'public',
        edit                => 'unique',
    },
);

__PACKAGE__->wing_child(
    employees    => {
        view            => 'public',
        related_class   => 'TestWing::DB::Result::Employee',
        related_id      => 'company_id',
    }
);

__PACKAGE__->wing_finalize_class( table_name => 'companies');

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);

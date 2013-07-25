package TestWing::DB::Result::Site;
use Moose;
use Wing::Perl;

extends 'Wing::DB::Result';
with 'Wing::Role::Result::Site';

__PACKAGE__->wing_finalize_class( table_name => 'sites');
no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);

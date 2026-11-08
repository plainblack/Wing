package TestWing::DB::Result::User;

use Moose;
use Wing::Perl;
use Ouch;
extends 'Wing::DB::Result';
with 'Wing::Role::Result::User';

__PACKAGE__->wing_privilege_fields(
    auditor => {refuse_app_tokens => 1},
);

__PACKAGE__->wing_finalize_class( table_name => 'users');

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);

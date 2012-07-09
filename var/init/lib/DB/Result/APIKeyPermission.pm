package [% project %]::DB::Result::APIKeyPermission;

use Moose;
use Wing::Perl;
extends 'Wing::DB::Result';
with 'Wing::Role::Result::APIKeyPermission';

__PACKAGE__->wing_finalize_class( table_name => 'api_key_permissions');

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);


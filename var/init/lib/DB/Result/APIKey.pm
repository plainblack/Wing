package [% project %]::DB::Result::APIKey;

use Moose;
use Wing::Perl;
extends 'Wing::DB::Result';
with 'Wing::Role::Result::APIKey';

__PACKAGE__->wing_finalize_class( table_name => 'api_keys');

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);

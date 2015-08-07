package [% project %]::DB::Result::TrendsReport;

use Moose;
use Wing::Perl;
extends 'Wing::DB::Result';
with 'Wing::Role::Result::TrendsReport';

__PACKAGE__->wing_finalize_class( table_name => 'trendsreports');

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);


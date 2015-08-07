package [% project %]::DB::Result::TrendsLogYearly;

use Moose;
use Wing::Perl;
extends 'Wing::DB::Result';
with 'Wing::Role::Result::TrendsLogYearly';
#with 'Wing::Role::Result::PrivilegeField';

#__PACKAGE__->wing_privilege_fields(
#    supervisor              => {},
#);

__PACKAGE__->wing_finalize_class( table_name => 'trends_logs_yearly');

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);


package [% project %]::DB::Result::TrendsLog;

use Moose;
use Wing::Perl;
extends 'Wing::DB::Result';
with 'Wing::Role::Result::TrendsLog';
#with 'Wing::Role::Result::PrivilegeField';

#__PACKAGE__->wing_privilege_fields(
#    supervisor              => {},
#);

__PACKAGE__->wing_finalize_class( table_name => 'trends_logs');

#around trend_deltas => sub {
#    my ($orig, $self) = @_;
#    my $out = $orig->($self);
#    $out->{groups_total} = sub { Wing->db->resultset('Group')->count };
#    return $out;
#};

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);


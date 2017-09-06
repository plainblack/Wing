package CS::DB::Result::IdeaSubscription;

use Moose;
use Wing::Perl;
use Ouch;
extends 'Wing::DB::Result';
with 'Wing::Role::Result::IdeaSubscription';


__PACKAGE__->wing_finalize_class( table_name => 'ideasubscriptions');


no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);

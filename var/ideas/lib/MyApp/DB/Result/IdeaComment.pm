package CS::DB::Result::IdeaComment;

use Moose;
use Wing::Perl;
use Ouch;
extends 'Wing::DB::Result';

with 'Wing::Role::Result::IdeaComment';

__PACKAGE__->wing_finalize_class( table_name => 'ideacomments');

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);

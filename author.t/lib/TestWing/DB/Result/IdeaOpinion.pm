package TestWing::DB::Result::IdeaOpinion;
use Moose;
use Wing::Perl;
extends 'Wing::DB::Result';
with 'Wing::Role::Result::IdeaOpinion';

__PACKAGE__->wing_finalize_class( table_name => 'ideaopinions');
no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);

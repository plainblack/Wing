package CS::DB::Result::Idea;

use Moose;
use Wing::Perl;
use Ouch;
use POSIX qw/ceil/;
use Time::Duration;
extends 'Wing::DB::Result';
with 'Wing::Role::Result::Idea';

__PACKAGE__->wing_finalize_class( table_name => 'ideas');

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);

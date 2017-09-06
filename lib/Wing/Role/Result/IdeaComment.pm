package Wing::Role::Result::IdeaComment;

use Wing::Perl;
use Wing;
use Ouch;
use Moose::Role;

with 'Wing::Role::Result::Parent';
use constant comment_relationship_name => 'idea';
with 'Wing::Role::Result::Comment';
use Wing::ContentFilter;

before wing_finalize_class => sub {
    my ($class) = @_;
    my $namespace = $class;
    $namespace =~ s/^(\w+)\:.*$/$1/;
    $class->wing_parent(
        idea   => {
            view                => 'public',
            edit                => 'required',
            related_class       => $namespace.'::DB::Result::Idea',
            skip_owner_check    => 1,
        }
    );
};

after insert => sub {
    my $self = shift;
    $self->idea->recalc_comment_count;
    $self->idea->notify_subscribers($self->user->display_name.' added a comment.', $self->user_id);
};

after delete => sub {
    my $self = shift;
    $self->idea->recalc_comment_count;
};

1;

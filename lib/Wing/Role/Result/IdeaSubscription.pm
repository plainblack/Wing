package Wing::Role::Result::IdeaSubscription;

use Wing::Perl;
use Wing;
use Ouch;
use Moose::Role;

with 'Wing::Role::Result::UserControlled';
with 'Wing::Role::Result::Parent';

before wing_finalize_class => sub {
    my ($class) = @_;
    my $namespace = $class;
    $namespace =~ s/^(\w+)\:.*$/$1/;
    $class->wing_parent(
        idea   => {
            view                => 'public',
            edit                => 'required',
            related_class       => $namespace.'::DB::Result::Idea',
        }
    );
};

after insert => sub {
    my $self = shift;
    $self->idea->recalc_subscription_count->update;
};

after delete => sub {
    my $self = shift;
    $self->idea->recalc_subscription_count->update;
};

sub notify {
    my ($self, $message, $user_id) = @_;
    return if defined $user_id && $user_id eq $self->user_id;
    eval {
        $self->user->send_templated_email('notify_about_idea', {
            idea               => $self->idea->describe(include_private => 1),
            message            => $message,
        },{
            wingman => 1,
        });
    };
}

1;

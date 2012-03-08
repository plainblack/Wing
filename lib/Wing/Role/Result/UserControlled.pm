package Wing::Role::Result::UserControlled;

use Wing::Perl;
use Ouch;
use Moose::Role;
with Wing::Role::Result::Parent;

before wing_finalize_class => sub {
    my ($class) = @_;
    $class->wing_parent(
        user    => {
            view        => 'public',
            edit        => 'required',
            related_class   => Wing->config->get('app_namespace').'::DB::Result::User',
        }
    ); 
};

around can_use => sub {
    my ($orig, $self, $user) = @_;
    return 1 if $self->user->can_use($user);
    return $orig->($self, $user);
};

1;

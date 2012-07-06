package Wing::Role::Result::PrivilegeControlled;

use Wing::Perl;
use Ouch;
use Moose::Role;


sub wing_controlled_by_privilege {
    my ($class, $privilege_name) = @_;
    my $is_method_name = 'is_'.$privilege_name;

    $class->meta->add_around_method_modifier( can_use => sub {
        my ($orig, $self, $user) = @_;
        return 1 if $user->$is_method_name;
        return $orig->($self, $user);
    });
}

1;

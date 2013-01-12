package Wing::Role::Result::PrivilegeControlled;

use Wing::Perl;
use Ouch;
use Moose::Role;

=head1 NAME

Wing::Role::Result::PrivilegeControlled - Make your Wing objects controllable by users with specific privileges.

=head1 SYNOPSIS

 with 'Wing::Role::Result::PrivilegeControlled';
 
 __PACKAGE__->wing_controlled_by_privilege('pizza_manager');

=head1 DESCRIPTION

Use this role in your object when you want to allow objects to be edited by users that have specific privileges that have been set in advance. Use L<Wing::Role::Result::PrivilegeField> to define those privileges.

=cut

sub wing_controlled_by_privilege {
    my ($class, $privilege_name) = @_;
    my $is_method_name = 'is_'.$privilege_name;

    $class->meta->add_around_method_modifier( can_edit => sub {
        my ($orig, $self, $user) = @_;
        return 1 if (defined $user && $user->$is_method_name);
        return $orig->($self, $user);
    });
}

1;

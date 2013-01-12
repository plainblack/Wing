package Wing::Role::Result::UserControlled;

use Wing::Perl;
use Ouch;
use Moose::Role;
with 'Wing::Role::Result::Parent';


=head1 NAME

Wing::Role::Result::UserControlled - Make your Wing objects controllable by registered users.

=head1 SYNOPSIS

 with 'Wing::Role::Result::UserControlled';

=head1 DESCRIPTION

Use this role in your object when you want to allow registered user created content, such as message board posts.

=head1 ADDS

=head2 Parents

=over

=item user

A reference to a user object.

=back

=cut


after wing_apply_relationships => sub {
    my ($class) = @_;
    my $namespace = $class;
    $namespace =~ s/^(\w+)\:.*$/$1/;
    $class->wing_parent(
        user    => {
            view        => 'public',
            edit        => 'required',
            related_class   => $namespace.'::DB::Result::User',
        }
    ); 
};

around can_use => sub {
    my ($orig, $self, $user) = @_;
    return 1 if $self->user->can_use($user);
    return $orig->($self, $user);
};

1;

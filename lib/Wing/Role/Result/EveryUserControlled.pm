package Wing::Role::Result::EveryUserControlled;

use Wing::Perl;
use Ouch;
use Moose::Role;
with 'Wing::Role::Result::Field';
with 'Wing::Role::Result::Parent';

=head1 NAME

Wing::Role::Result::EveryUserControlled - Wing object may be controlled by any user so long as they are logged in.

=head1 SYNOPSIS

 with 'Wing::Role::Result::EveryUserControlled';

=head1 DESCRIPTION

Use this role in your object when you want to allow user created content on your site that is shared among users. It's good for tags as an example.

=cut


around can_edit => sub {
    my ($orig, $self, $user, $tracer) = @_;
    if (defined $user && ref($user) =~ m/User/) {
        return 1; 
    }
    return $orig->($self, $user);
};


1;

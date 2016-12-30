package Wing::Role::Result::UriPart;

use Wing::Perl;
use Ouch;
use Data::GUID;
use Moose::Role;

with 'Wing::Role::Result::Urlize';

=head1 NAME

Wing::Role::Result::UriPart - Give your Wing object a URL fragment.

=head1 SYNOPSIS

 with 'Wing::Role::Result::UriPart';

=head1 DESCRIPTION

Create an automatically defined URL for an object based upon it's name. The uri_part will be unique amongst other objects of the same type, by appending an integer to the end if necessary. If the name cannot be turned into a uri_part for some reason it will ouch 443. The C<uri_part> is automatically set whenever the C<name> field is modified.

=head1 SEE ALSO

L<Wing::Role::Result::Urlize>
L<Wing::Role::Result::UriPartOnInit>

=head1 REQUIREMENTS

The class you load this into must have a C<name> field defined.

=head1 ADDS

=head2 Fields

=over

=item uri_part

A URL-safe version of the C<name> field. This is automatically generated and gracefully supports UTF-8 whenever the C<name> field is modified.

=back

=cut


before wing_finalize_class => sub {
    my ($class) = @_;
    $class->wing_field(
        uri_part => {
            dbic            => { data_type => 'varchar', size => 60, is_nullable => 0 },
            view            => 'public',
            indexed         => 'unique',
            skip_duplicate  => 1,
        }
    );
};

after wing_finalize_class => sub {
    my $class = shift;
    $class->meta->add_after_method_modifier('name', sub {
        my $self = shift;
        my $name = shift;
        $self->set_uri_part($name, $class);
    });
};

1;

package Wing::Role::Result::UriPartOnInit;

use Wing::Perl;
use Ouch;
use Data::GUID;
use Moose::Role;

with 'Wing::Role::Result::Urlize';

=head1 NAME

Wing::Role::Result::UriPartOnInit - Give your Wing object a URL fragment when it is created.

=head1 SYNOPSIS

 with 'Wing::Role::Result::UriPart';

=head1 DESCRIPTION

Identical to L<Wing::Role::Result::UriPart> except that the C<uri_part> field is only automatically generated if C<uri_part> is currently empty or null.

=head1 SEE ALSO

L<Wing::Role::Result::Urlize>
L<Wing::Role::Result::UriPart>

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
            dbic        => { data_type => 'varchar', size => 60, is_nullable => 0 },
            view        => 'public',
            indexed     => 'unique',
        }
    );
};

after wing_finalize_class => sub {
    my $class = shift;
    $class->meta->add_after_method_modifier('name', sub {
        my $self = shift;
        my $name = shift;
        if (!$self->uri_part) {
            $self->set_uri_part($name, $class);
        }
    });
};

1;

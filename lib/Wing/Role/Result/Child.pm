package Wing::Role::Result::Child;

use Wing::Perl;
use Ouch;
use Moose::Role;
with 'Wing::Role::Result::Field';

sub register_children {
    my ($class, %fields) = @_;
    while (my ($field, $definition) = each %fields) {
        $class->register_child($field, $definition);
    }
}

sub register_child {
    my ($class, $field, $options) = @_;

    # create relationship
    my @relationship = ($field, $options->{related_class}, $options->{related_id});
    $class->has_many(@relationship);
    
    # add relationship to describe
    $class->meta->add_around_method_modifier(describe => sub {
        my ($orig, $self, %describe_options) = @_;
        my $out = $orig->($self, %describe_options);
        my $describe = sub {
            if ($describe_options{include_relationships}) {
                $out->{_relationships}{$field} = $self->object_api_uri.'/'.$field;
            }
        };
        if (exists $options->{view}) {
            if ($options->{view} eq 'admin') {
                $describe->() if ($describe_options{include_admin} || (exists $describe_options{current_user} && defined $describe_options{current_user} && $describe_options{current_user}->is_admin));
            }
            elsif ($options->{view} eq 'private') {
                $describe->() if ($describe_options{include_private} || eval { $self->can_use($describe_options{current_user}) });
            }
            elsif ($options->{view} eq 'public') {
                $describe->(); 
            }
        }
        return $out;
    });

}

1;

=head1 NAME

Wing::Role::Result::Child

=head1 DESCRIPTION

Create descendant relationships from the class that consumes this role.

=head1 METHODS

=head2 register_child

=over

=item name

Scalar. The name of the relationship.

=item options

Hash reference. All of the options from L<Wing::Role::Result::Field> C<register_field> except for C<dbic> and C<edit>, plus the following ones:

=over

=item related_class

The L<Wing::DB::Result> subclass that this object should be related to.

=item related_id

The name of the field in C<related_class> that maps to the C<id> of the consuming object.

=back

=back

=head2 register_children

The same as C<register_child>, but takes a hash of relationships rather than just a single one.

=over

=item relationships

Hash. The names are the names of the relationships and the values are the C<options> from C<register_child>.

=back

=cut
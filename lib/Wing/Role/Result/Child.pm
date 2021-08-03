package Wing::Role::Result::Child;

use Wing::Perl;
use Ouch;
use Moose::Role;
with 'Wing::Role::Result::Field';

sub wing_children {
    my ($class, %fields) = @_;
    while (my ($field, $definition) = each %fields) {
        $class->wing_child($field, $definition);
    }
}

sub wing_child {
    my ($class, $field, $options) = @_;

    # create relationship
    my @relationship = ($field, $options->{related_class}, $options->{related_id});
    $class->meta->add_after_method_modifier(wing_apply_relationships => sub {
        my $my_class = shift;
        $my_class->has_many(@relationship);
    });
        
    # make note of the relationship
    $class->meta->add_around_method_modifier(relationship_accessors => sub {
        my ($orig, $self) = @_;
        my $params = $orig->($self);
        push @$params, $field;
        return $params;
    });

    # add relationship to describe
    $class->meta->add_around_method_modifier(describe => sub {
        my ($orig, $self, %describe_options) = @_;
        my $out = $orig->($self, %describe_options);
        my $describe = sub {
            if ($describe_options{include_relationships}) {
                $out->{_relationships}{$field} = $self->wing_object_api_uri.'/'.$field;
            }
        };
        if (exists $options->{view}) {
            if ($options->{view} eq 'admin') {
                $describe->() if $describe_options{include_admin} || $self->check_privilege_method($options->{check_privilege}, $describe_options{current_user});
            }
            elsif ($options->{view} eq 'private') {
                $describe->() if $describe_options{include_private} || $self->check_privilege_method($options->{check_privilege}, $describe_options{current_user});
            }
            elsif ($options->{view} eq 'public') {
                $describe->(); 
            }
        }
        return $out;
    });
    
    # add a shortcut to adding a new child
    $class->meta->add_method( 'wing_add_to_'.$field => sub {
        my $self = shift;
        my $child = $self->result_source->schema->resultset($options->{related_class})->new({});
        my $method = $options->{related_id};
        $child->$method($self->id);
        return $child;
    });

}

1;

=head1 NAME

Wing::Role::Result::Child

=head1 DESCRIPTION

Create descendant relationships from the class that consumes this role.

=head1 METHODS

=head2 wing_child

=over

=item name

Scalar. The name of the relationship.

=item options

Hash reference. All of the options from L<Wing::Role::Result::Field> C<wing_field> except for C<dbic> and C<edit>, plus the following ones:

=over

=item related_class

The L<Wing::DB::Result> subclass that this object should be related to.

=item related_id

The name of the field in C<related_class> that maps to the C<id> of the consuming object.

=back

=back

=head2 wing_children

The same as C<wing_child>, but takes a hash of relationships rather than just a single one.

=over

=item relationships

Hash. The names are the names of the relationships and the values are the C<options> from C<wing_child>.

=back

=head1 RESULT

The result object will be changed in these ways:

=over

=item Adds a C<has_many>

Adds a L<DBIx::Class> C<has_many> relationship.

=item Updates C<describe>

Adds the child relationship to the C<describe> method.

=item Adds C<wing_add_to_$relationship_name> Method

Exactly like the C<add_to_$rel> method created by L<DBIx::Class::Relationship::Base> except that it doesn't insert the object, it waits for you to insert it.

=back

=cut

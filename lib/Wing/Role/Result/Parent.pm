package Wing::Role::Result::Parent;

use Wing::Perl;
use Ouch;
use Moose::Role;
with 'Wing::Role::Result::Field';

sub register_parent_field {
    my ($class, $field, $options) = @_;
    my $id = $options->{related_id} || $field.'_id';
    my %dbic = ( data_type => 'char', size => 36, is_nullable => 1 );
    if ($options->{edit} ~~ [qw(required unique)]) {
        $dbic{is_nullable} = 0;
    }
    
    # create the field
    $options->{dbic} = \%dbic;
    $class->register_field($id, $options);

    # validation
    $class->meta->add_before_method_modifier($id => sub {
        my ($self, $value) = @_;
        if (defined $value) {
            my $object = Wing->db->resultset($options->{related_class})->find($value);
            ouch(440, $id.' specified does not exist.', $id) unless defined $object;
            $self->$field($object);
        }
    });
    $class->meta->add_before_method_modifier(verify_posted_params => sub {
        my ($self, $params, $current_user) = @_;
        if (exists $params->{$id}) {
            ouch(441, $id.' is required.', $id) unless $params->{$id};
            my $object = Wing->db->resultset($options->{related_class})->find($params->{$id});
            ouch(440, $id.' not found.') unless defined $object;
            $object->can_use($current_user);
            $self->$field($object);
        }
    });

    # generate options
    if ($options->{generate_options_by_name}) {
        $class->meta->add_around_method_modifier(field_options => sub {
            my ($orig, $self) = @_;
            my $out = $orig->($self);
            my @parent_ids;
            my %parent_options;
            my $parents = Wing->db->resultset($options->{related_class})->search(undef,{order_by => 'name'});
            while (my $parent = $parents->next) {
                push @parent_ids, $parent->id;
                $parent_options{$parent->id} = $parent->name;
            }
            $out->{$id} = \@parent_ids;
            $out->{'_'.$id} = \%parent_options;
            return $out;
        });
    }
}

sub register_parent_relationship {
    my ($class, $field, $options) = @_;
    my $id = $options->{related_id} || $field.'_id';
    my @relationship = ($field, $options->{related_class}, $id);
    unless ($options->{edit} ~~ [qw(required unique)]) {
        push @relationship, { on_delete => 'set null' };
    }
    # create relationship
    $class->belongs_to(@relationship);
    
    # add relationship to describe
    $class->meta->add_around_method_modifier(describe => sub {
        my ($orig, $self, %describe_options) = @_;
        my $out = $orig->($self, %describe_options);
        my $describe = sub {
            if ($describe_options{includ_related_objects}) {
                $out->{$field} = $self->$field->describe;
            }
            if ($describe_options{include_relationships}) {
                $out->{_relationships}{$field} = '/api/'.$options->{related_class}->object_type.'/'.$self->$id if $self->$id;
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

sub register_parents {
    my ($class, %fields) = @_;
    while (my ($field, $options) = each %fields) {
        $class->register_parent_field($field, $options);
        $class->register_parent_relationship($field, $options);
    }
}

sub register_parent {
    my ($class, $field, $options) = @_;
}

1;

=head1 NAME

Wing::Role::Result::Parent

=head1 DESCRIPTION

Create parental relationships from the class that consumes this role.

=head1 METHODS

=head2 register_parent

=over

=item name

Scalar. The name of the relationship.

=item options

Hash reference. All of the options from L<Wing::Role::Result::Field> C<register_field> except for C<dbic>, plus the following ones.

=over

=item related_class

Scalar. The L<Wing::DB::Result> subclass that this object should be related to.

=item related_id

Scalar. Optional. The field to be created in this class to store the relationship. If left undefined it will be generated as C<name> + C<_id> (C<name_id>).

=item generate_options_by_name

Boolean. Optional. Defaults to C<0>. If set to C<1> this will add an enumerated options list to the object description when C<include_options> is specified. The options will be C<id> / C<name> pairs. 

=back

=back

=head2 register_parents

The same as C<register_parent>, but takes a hash of relationships rather than just a single one.

=over

=item relationships

Hash. The names are the names of the relationships and the values are the C<options> from C<register_parent>.

=back

=cut
package Wing::Role::Result::Parent;

use Wing::Perl;
use Ouch;
use Moose::Role;
with 'Wing::Role::Result::Field';
no warnings 'experimental::smartmatch';

sub wing_parent_field {
    my ($wing_object_class, $field, $options) = @_;
    my $id = $options->{related_id} || $field.'_id';
    my %dbic = ( data_type => 'char', size => 36, is_nullable => 1 );
    if ($options->{edit} ~~ [qw(required unique)]) {
        $dbic{is_nullable} = 0;
    }
    
    # create the field
    $options->{dbic} = \%dbic;
    $wing_object_class->wing_field($id, $options);

    $wing_object_class->meta->add_after_method_modifier(wing_apply_fields => sub {
        my $class = shift;

        # validation
        unless ($options->{skip_ref_check}) {
            $class->meta->add_before_method_modifier($id => sub {
                my ($self, $value) = @_;
                if (defined $value) {
                    my $object = $self->result_source->schema->resultset($options->{related_class})->find($value);
                    ouch(440, $id.' specified does not exist.', $id) unless defined $object;
                    $self->$field($object);
                }
            });
        }
        $class->meta->add_before_method_modifier(verify_posted_params => sub {
            my ($self, $params, $current_user) = @_;
            if (exists $params->{$id}) {
                if (! defined $params->{$id} && $options->{edit} !~ [qw(required unique)]) {
                    $self->$id(undef);
                }
                else {
                    ouch(441, $id.' is required.', $id) unless $params->{$id};
                    my $object = $self->result_source->schema->resultset($options->{related_class})->find($params->{$id});
                    ouch(440, $id.' not found.') unless defined $object;
                    $object->can_link_to($current_user) unless $options->{skip_owner_check};
                    $self->$field($object);
                }
            }
        });
    
        # generate options
        if ($options->{generate_options_by_name}) {
            $class->meta->add_around_method_modifier(field_options => sub {
                my ($orig, $self, %describe_options) = @_;
                my $out = $orig->($self, %describe_options);
                my @parent_ids;
                my %parent_options;
                my $parents = $self->result_source->schema->resultset($options->{related_class})->search(undef,{order_by => 'name'});
                while (my $parent = $parents->next) {
                    push @parent_ids, $parent->id;
                    $parent_options{$parent->id} = $parent->name;
                }
                $out->{$id} = \@parent_ids;
                $out->{'_'.$id} = \%parent_options;
                return $out;
            });
        }
    });
}

sub wing_parent_relationship {
    my ($class, $field, $options) = @_;
    my $id = $options->{related_id} || $field.'_id';

    # create relationship
    my @relationship = ($field, $options->{related_class}, $id);
    unless ($options->{edit} ~~ [qw(required unique)]) {
        push @relationship, { on_delete => 'set null', join_type => 'left' };
    }
    $class->meta->add_after_method_modifier(wing_apply_relationships => sub {
        my $my_class = shift;
        $my_class->belongs_to(@relationship);
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
            if (exists $describe_options{include_related_objects}) {
                if ((ref $describe_options{include_related_objects} eq 'ARRAY' && $field ~~ $describe_options{include_related_objects}) || (ref $describe_options{include_related_objects} ne 'ARRAY' && $describe_options{include_related_objects})) {
                    if ($self->$id) {
			if ($self->$field eq undef) {
				ouch 440, $field.' ('.$self->$id.') does not exist for '.$self->wing_object_name.' ('.$self->id.').';
			}
			else { 
                        	$out->{$field} = $self->$field->describe;
			}
                    }
                }
            }
            if ($describe_options{include_relationships} && $self->$id) {
                $out->{_relationships}{$field} = '/api/'.$options->{related_class}->wing_object_type.'/'.$self->$id;
            }
            return $out;
        };
        if (exists $options->{view}) {
            if ($options->{view} eq 'admin') {
                $describe->() if $describe_options{include_admin};
            }
            elsif ($options->{view} eq 'private') {
                $describe->() if $describe_options{include_private};
            }
            elsif ($options->{view} eq 'public') {
                $describe->(); 
            }
        }
        return $out;
    });
}

sub wing_parents {
    my ($class, %fields) = @_;
    while (my ($field, $options) = each %fields) { # fields must be registered before relationships get applied
        $class->wing_parent_field($field, $options);
    }
    while (my ($field, $options) = each %fields) {
        $class->wing_parent_relationship($field, $options);
    }
}

sub wing_parent {
    my ($class, $field, $options) = @_;
    $class->wing_parent_field($field, $options);
    $class->wing_parent_relationship($field, $options);
}

1;

=head1 NAME

Wing::Role::Result::Parent

=head1 DESCRIPTION

Create parental relationships from the class that consumes this role.

=head1 METHODS

=head2 wing_parent

=over

=item name

Scalar. The name of the relationship.

=item options

Hash reference. All of the options from L<Wing::Role::Result::Field> C<wing_field> except for C<dbic>, plus the following ones.

=over

=item related_class

Scalar. The L<Wing::DB::Result> subclass that this object should be related to.

=item related_id

Scalar. Optional. The field to be created in this class to store the relationship. If left undefined it will be generated as C<name> + C<_id> (C<name_id>).

=item generate_options_by_name

Boolean. Optional. Defaults to C<0>. If set to C<1> this will add an enumerated options list to the object description when C<include_options> is specified. The options will be C<id> / C<name> pairs. 

=item skip_ref_check

Boolean. Optional. Normally adding a parent adds a check to make sure that the id that refers to a parent actually exists. When C<skip_ref_checK> is true that validation is skipped. This is really only useful if you want to create the parent at the same time you insert this object into the database.

=item skip_owner_check

Boolean. Optional. Normally adding a parent checks to see that you C<can_link_to> the object in question. When this is set, that check is disabled.

=back

=back

=head2 wing_parents

The same as C<wing_parent>, but takes a hash of relationships rather than just a single one.

=over

=item relationships

Hash. The names are the names of the relationships and the values are the C<options> from C<wing_parent>.

=back

=cut

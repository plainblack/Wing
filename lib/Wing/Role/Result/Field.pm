package Wing::Role::Result::Field;

=head1 NAME

Wing::Role::Result::Field - Some sugar to add fields to your wing classes.

=head1 SYNOPSIS

 with 'Wing::Role::Result::Field';
 
 __PACKAGE__->wing_field( 
    'name' => {
        dbic    => { data_type => 'varchar', size => 30 },
        edit  => 'unique',
    }
 );
 
=head1 METHODS

=cut

use Wing::Perl;
use Ouch;
use Moose::Role;


=head2 wing_fields(fields)

Add multiple fields at once. See C<wing_field> for details.

=over

=item fields

A hash of fields.

=back

=cut

sub wing_fields {
    my ($class, %fields) = @_;
    while (my ($field, $definition) = each %fields) {
        $class->wing_field($field, $definition);
    }
}

=head2 wing_field(field, options)

Add a field to your class.

=over

=item field

The name of the field. A method will be created as a getter/setter using this name.

=item options

A hash reference of the options that define the field.

=over

=item dbic

The L<DBIx::Class> field definition. Required.

=item edit

Can this field be edited through web/rest? There are several options:

=over

=item postable

Editable by anybody that controls the object.

=item required

The same as C<postable> and also required at object creation.

=item unique

The same as C<required> and is also required to be unique amongst all objects of this type.

=item admin

The same as C<postable>, but only editable by users with the admin bit flipped.

=back

=item indexed

Boolean. Indicates whether this field should have an index applied to it in the database for quicker searching. This is automatic when C<edit> is set to C<unique>.

B<NOTE:> If you set this specifically to C<unique> then it will create a unique index rather than a normal index.

=item range

An array reference where the first value is the minimum value in the range and the second is the max value.

=item options

An enumerated list of scalars as options for this field. 

=item describe_method

The name of a method in this class. This method will be called when C<describe> is called on the object to serialize this field. Most fields don't need special serialziation so most of the time this isn't necessary.

=item skip_duplicate

Boolean. When this is true then the C<duplicate> method will not copy this field while making a duplicate.

=item duplicate_prefix

If you set this, it will be prepended to the field when duplicated. This is useful for doing things like 'Copy of '. 

=back

=back

=cut

sub wing_field {
    my ($wing_object_class, $field, $options) = @_;

    $wing_object_class->meta->add_around_method_modifier(wing_apply_fields => sub {
        my ($orig, $class) = @_;
        $orig->($class);
        
        # add dbic columns
        $class->add_columns($field => $options->{dbic});
        
        # add field to postable params
        if (exists $options->{edit}) {
            if ($options->{edit} ~~ [qw(postable required unique)]) {
                $class->meta->add_around_method_modifier(postable_params => sub {
                    my ($orig, $self) = @_;
                    my $params = $orig->($self);
                    push @$params, $field;
                    return $params;
                });
    
                # make required
                if ($options->{edit} ~~ [qw(required unique)]) {
                    $class->meta->add_around_method_modifier(required_params => sub {
                        my ($orig, $self) = @_;
                        my $params = $orig->($self);
                        push @$params, $field;
                        return $params;
                    });
                    $class->meta->add_before_method_modifier($field => sub {
                        if (scalar @_ == 2 && ! defined $_[1]) {
                            ouch 441, $field.' is required.', $field;
                        }
                    });
                    
                    # make unique
                    if ($options->{edit} eq 'unique') {
                        $class->meta->add_before_method_modifier($field => sub {
                            my ($self, $value) = @_;
                            if (scalar(@_) > 1) {
                                my $criteria = { $field => $value };
                                if ($self->in_storage) {
                                    $criteria->{id} = { '!=' => $self->id };
                                }
                                ouch(443, $field.' not available.', $field) if $self->result_source->schema->resultset($class)->search($criteria)->count;
                            }
                        });
                    }
                }
            }
            elsif ($options->{edit} eq 'admin') {
                $class->meta->add_around_method_modifier(admin_postable_params => sub {
                    my ($orig, $self) = @_;
                    my $params = $orig->($self);
                    push @$params, $field;
                    return $params;
                });
            }
        }
    
        # add field to viewable params
        if (exists $options->{view}) {
            if ($options->{edit} eq 'public') {
                $class->meta->add_around_method_modifier(public_params => sub {
                    my ($orig, $self) = @_;
                    my $params = $orig->($self);
                    push @$params, $field;
                    return $params;
                });
            }
            elsif ($options->{view} eq 'private') {
                $class->meta->add_around_method_modifier(private => sub {
                    my ($orig, $self) = @_;
                    my $params = $orig->($self);
                    push @$params, $field;
                    return $params;
                });
            }
            elsif ($options->{view} eq 'admin') {
                $class->meta->add_around_method_modifier(admin_viewable_params => sub {
                    my ($orig, $self) = @_;
                    my $params = $orig->($self);
                    push @$params, $field;
                    return $params;
                });
            }
        }
    
        # add index
        if (exists $options->{indexed} && $options->{indexed} eq 'unique' || exists $options->{edit} && $options->{edit} eq 'unique') {
            $class->add_unique_constraint([$field]);
        }
        elsif (exists $options->{indexed} && $options->{indexed}) {
            $class->meta->add_around_method_modifier(sqlt_deploy_hook => sub {
                my ($orig, $self, $sqlt_table) = @_;
                $orig->($self, $sqlt_table);
                $sqlt_table->add_index(name => 'idx_'.$field, fields => [$field]);
            });
        }
        
        # range validation
        if (exists $options->{range}) {
            if (ref $options->{range} ne 'ARRAY') {
                ouch 500, 'Range for "'.$field.'" must be specified with an array reference.';
            }
            $class->meta->add_before_method_modifier($field => sub {
                my ($self, $value) = @_;
                if (scalar(@_) > 1) {
                    my $min = $options->{range}[0];
                    my $max = $options->{range}[1];
                    unless ($value >= $min && $value <= $max) {
                        ouch 442, $field.' must be between '.$min.' and '.$max.'.', $field;
                    }
                }
            });
        }
    
        # enumerated validation
        if (exists $options->{options}) {
            if (ref $options->{options} ne 'ARRAY') {
                ouch 500, 'Options for "'.$field.'" must be specified with an array reference.';
            }
            $class->meta->add_method( $field.'_options' => sub {
                my $self = shift;
                return $options->{options};
            });
            $class->meta->add_around_method_modifier(field_options => sub {
                my ($orig, $self) = @_;
                my $existing = $orig->($self);
                $existing->{$field} = $options->{options};
                if (exists $options->{_options}) {
                    if (ref $options->{_options} ne 'HASH') {
                        ouch 500, 'Human readable options for "'.$field.'" must be specified with a hash reference.';
                    }
                    $existing->{'_'.$field} = $options->{_options};
                }
                else {
                    foreach my $option (@{$options->{options}}) {
                        $existing->{'_'.$field}{$option} = $option;
                    }
                }
                return $existing;
            });
            $class->meta->add_before_method_modifier($field => sub {
                my ($self, $value) = @_;
                if (scalar(@_) > 1) {
                    unless ($value ~~ $options->{options}) {
                        ouch 442, $field.' must be one of: '.join(', ', @{$options->{options}}). " and not ".$value, $field;
                    }
                }
            });
        }
    
        # add field to describe
        $class->meta->add_around_method_modifier(describe => sub {
            my ($orig, $self, %describe_options) = @_;
            my $out = $orig->($self, %describe_options);
            my $describe = sub {
                my $method = $field;
                if (exists $options->{describe_method}) {
                    $method = $options->{describe_method};
                }
                $out->{$field} = $self->$method;
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
        
        # duplicate fields
        $class->meta->add_around_method_modifier(duplicate => sub {
            my ($orig, $self) = @_;
            my $dup = $orig->($self);
            if ($options->{skip_duplicate}) {
                # do nothing
            }
            else {
                my $value = $self->$field();
                if ($options->{duplicate_prefix}) {
                    $value = $options->{duplicate_prefix}.$value;
                }
                $dup->$field($value);
            }
            return $dup;
        });
    });
}

1;

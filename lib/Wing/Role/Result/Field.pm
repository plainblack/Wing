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
use List::MoreUtils qw(any);


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

B<NOTE:> If you use C<is_auto_increment> then the field will automatically get a C<unique> index and Wing will automatically fetch the autoincremented value back from the database after C<insert()>.

=item view

Can this field be viewed through web/rest? There are several options:

=over

=item public

Anybody can view it.

=item private

Viewable by anybody that passes muster with the C<can_view> method.

=item admin

Viewable only by admins.

=back

=item edit

Can this field be edited through web/rest? There are several options:

=over

=item postable

Editable by anybody that controls the object through the C<can_edit> method.

=item required

The same as C<postable> and also required at object creation.

=item unique

The same as C<required> and is also required to be unique amongst all objects of this type.

=item admin

The same as C<postable>, but only editable by users with the admin bit flipped.

=back

=item check_privilege

Specifies the name of a method to call to verify whether the current user is allowed to update this field. The method needs to take an array of arguments including C<current_user>, C<field_name>, and C<new_field_value>. And must return either a 1 if the field is allowed to be updated, or L<Ouch> 450 if the field is not allowed to be updated. Example method:

 sub check_user_is_cool {
     my ($self, $current_user, $field, $value) = @_;
     unless ($current_user->is_in_group('Cool People')) { # using a hypothetical is_in_group method
         ouch 450, $current_user->display_name.' not cool enough to edit '.$field;
     }
 }

=item indexed

Boolean. Indicates whether this field should have an index applied to it in the database for quicker searching. This is automatic when C<edit> is set to C<unique>.

B<NOTE:> If you set this specifically to C<unique> then it will create a unique index rather than a normal index.

=item unique_qualifiers

Array reference of field names. If the field gets marked unique as an index or by making edit unique, by default it needs to be unique amongst all objects of this type. However, you can add extra fields to qualify the uniqueness against and then it will be unique within that set. For example, if you have a field called C<name> that you want to be unique, but you have a column called C<category> then you could specify unique_qualifiers as C<['category']> and then have a unique name per category.

=item filter

A subroutine reference that will test and fix the value supplied. For example, you might use L<URI::Heuristic> to do the following:

 __PAKCAGE__->wing_field(
     website_uri => {
        dbic           => { data_type => 'varchar', size => 255, is_nullable => 0, default_value => 'http://' },
        view           => 'public',
        edit           => 'postable',
        filter         => sub {
            return URI::Heuristic::uf_uristr($_[0]);
        },
     }
 );

=item range

An array reference where the first value is the minimum value in the range and the second is the max value.

=item options

An enumerated list of scalars as options for this field. Alternatively you can pass in a code reference. The code reference will be passed a reference to this object (though it may not be inserted into the database yet), and the L<Wing::DB::Result> C<describe> options, if they are available.

Example of using a code ref:

 options => sub {
     my ($self, %options) = @_;
     if (exists $options{current_user} && defined $options{current_user}) {
         return [1..$options{current_user}->age];
     },
     else {
         return [1..120];
     }
 },

Including options will also generate a method in your class called C<field_name_options>. So if your field name is C<color> then the method generated would be C<color_options>. This method is then called by C<field_options> for generating the options on web services.


=item _options

A hash where the keys are the previously defined C<options> array, and the values are the human readable labels.

Including options will also generate a method in your class called C<_field_name_options>. So if your field name is C<color> then the method generated would be C<_color_options>. This method is then called by C<field_options> for generating the options on web services.

=item describe_method

The name of a method in this class. This method will be called when C<describe> is called on the object to serialize this field. Most fields don't need special serialziation so most of the time this isn't necessary.

=item skip_duplicate

Boolean. When this is true then the C<duplicate> method will not copy this field while making a duplicate.

=item duplicate_prefix

If you set this, it will be prepended to the field when duplicated. This is useful for doing things like 'Copy of '.

=item skip_unique_if_null

If you set this, the unique value checks done inside Wing will be skipped.

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
            # add privilege check
            if (exists $options->{check_privilege}) {
                $class->meta->add_around_method_modifier(privileged_params => sub {
                    my ($orig, $self) = @_;
                    my $params = $orig->($self);
                    $params->{$field} = $options->{check_privilege};
                    return $params;
                });

            }

            if (any {$_ eq $options->{edit}} (qw(postable required unique))) {
                $class->meta->add_around_method_modifier(postable_params => sub {
                    my ($orig, $self) = @_;
                    my $params = $orig->($self);
                    push @$params, $field;
                    return $params;
                });

                # make required
                if (any {$_ eq $options->{edit}} (qw(required unique))) {
                    $class->meta->add_around_method_modifier(required_params => sub {
                        my ($orig, $self) = @_;
                        my $params = $orig->($self);
                        push @$params, $field;
                        return $params;
                    });
                    $class->meta->add_before_method_modifier($field => sub {
                        if (scalar @_ == 2 && (! defined $_[1] || $_[1] eq '')) {
                            ouch 441, $field.' is required.', $field;
                        }
                    });
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
            if ($options->{view} eq 'public') {
                $class->meta->add_around_method_modifier(public_params => sub {
                    my ($orig, $self) = @_;
                    my $params = $orig->($self);
                    push @$params, $field;
                    return $params;
                });
            }
            elsif ($options->{view} eq 'private') {
                $class->meta->add_around_method_modifier(private_params => sub {
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
        if ((exists $options->{indexed} && $options->{indexed} eq 'unique') || (exists $options->{edit} && $options->{edit} eq 'unique') || (exists $options->{dbic}{is_auto_increment} && $options->{dbic}{is_auto_increment})) {
            my @constraint = $field;
            if ($options->{unique_qualifiers}) {
                push @constraint, @{$options->{unique_qualifiers}};
            }
            $class->add_unique_constraint(\@constraint);
        }
        elsif (exists $options->{indexed} && $options->{indexed}) {
            $class->meta->add_around_method_modifier(sqlt_deploy_hook => sub {
                my ($orig, $self, $sqlt_table) = @_;
                $orig->($self, $sqlt_table);
                $sqlt_table->add_index(name => 'idx_'.$field, fields => [$field]);
            });
        }

        # add unique precheck
        if ((exists $options->{indexed} && $options->{indexed} eq 'unique') || (exists $options->{edit} && $options->{edit} eq 'unique')) {
            my $check = sub {
                my $self = shift;
                return if $options->{skip_unique_if_null} && ! defined $self->$field();
                my $criteria = { $field => $self->$field() };
                if ($self->in_storage) {
                    $criteria->{id} = { '!=' => $self->id };
                }
                if ($options->{unique_qualifiers}) {
                    foreach my $qualifier (@{$options->{unique_qualifiers}}) {
                        $criteria->{$qualifier} = $self->$qualifier();
                    }
                }
                ouch(443, $field.' must be unique, and '.$self->$field().' has already been used.', $field) if $self->result_source->schema->resultset($class)->search($criteria)->count;
            };
            $class->meta->add_before_method_modifier('insert' => $check);
            $class->meta->add_before_method_modifier('update' => sub {
                my $self = shift;
                my %cols = $self->get_dirty_columns;;
                my $dirty = exists $cols{$field} ? 1 : 0;
                if ($options->{unique_qualifiers}) {
                    foreach my $qualifier (@{$options->{unique_qualifiers}}) {
                        if (exists $cols{$qualifier}) {
                            $dirty = 1;
                        }
                    }
                }
                if ($dirty) {
                    $check->($self);
                }
            });
        }

        # fetch values back from db
        if (exists $options->{dbic}{is_auto_increment} && $options->{dbic}{is_auto_increment}) {
            $class->meta->add_after_method_modifier(insert => sub {
                my $self = shift;
                $self->discard_changes;
            });
        }

        # filter
        if (exists $options->{filter}) {
            if (ref $options->{filter} ne 'CODE') {
                ouch 500, 'Filter for "'.$field.'" must be specified with a code reference.';
            }
            $class->meta->add_around_method_modifier($field => sub {
                my ($orig, $self, $value) = @_;
                if (scalar(@_) > 2) {
                    $orig->($self, $options->{filter}->($value));
                }
                else {
                    $orig->($self);
                }
            });
        }

        # enumerated validation
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
            if (ref $options->{options} ne 'ARRAY' && ref $options->{options} ne 'CODE') {
                ouch 500, 'Options for "'.$field.'" must be specified with an array reference or code reference.';
            }
            my $field_options_method = $field.'_options';
            $class->meta->add_method( $field_options_method => sub {
                my ($self, %describe_options) = @_;
                if (ref $options->{options} eq 'CODE') {
                    return $options->{options}->($self, %describe_options);
                }
                else {
                    return $options->{options};
                }
            });
            my $_field_options_method = '_'.$field.'_options';
            $class->meta->add_method( $_field_options_method => sub {
                my ($self, %describe_options) = @_;
                if (ref $options->{_options} eq 'CODE') {
                    return $options->{_options}->($self, %describe_options);
                }
                else {
                    return $options->{_options};
                }
            });
            $class->meta->add_around_method_modifier(field_options => sub {
                my ($orig, $self, %describe_options) = @_;
                my $existing = $orig->($self, %describe_options);
                $existing->{$field} = $self->$field_options_method(%describe_options);
                if (exists $options->{_options}) {
                    if (ref $options->{_options} ne 'HASH' || ref $options->{_options} ne 'CODE') {
                        ouch 500, 'Human readable options for "'.$field.'" must be specified with a hash or code reference.';
                    }
                    $existing->{'_'.$field} = $options->{_options};
                }
                else {
                    foreach my $option (@{$existing->{$field}}) {
                        $existing->{'_'.$field}{$option} = $option;
                    }
                }
                return $existing;
            });
            $class->meta->add_before_method_modifier($field => sub {
                my ($self, $value) = @_;
                my $options = $self->$field_options_method;
                if (scalar(@_) > 1 && defined $options) {
                    unless (any {$_ eq $value} @$options) {
                        ouch 442, $field.' must be one of: '.join(', ', @{$options}). " and not ".$value, $field;
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

        # duplicate fields
        $class->meta->add_around_method_modifier(duplicate => sub {
            my ($orig, $self) = @_;
            my $dup = $orig->($self);
            if ((exists $options->{skip_duplicate} && $options->{skip_duplicate}) || (exists $options->{dbic}{is_auto_increment} && $options->{dbic}{is_auto_increment})) {
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

package Wing::Role::Result::Field;

use Wing::Perl;
use Ouch;
use Moose::Role;

sub wing_fields {
    my ($class, %fields) = @_;
    while (my ($field, $definition) = each %fields) {
        $class->wing_field($field, $definition);
    }
}

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
                        ouch 442, $field.' must be one of: '.join(', ', @{$options->{options}}), $field;
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
            if ($options->{no_duplicate}) {
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

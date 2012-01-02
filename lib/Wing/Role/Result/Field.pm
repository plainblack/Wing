package Wing::Role::Result::Field;

use Wing::Perl;
use Ouch;
use Moose::Role;

sub register_fields {
    my ($class, %fields) = @_;
    while (my ($field, $definition) = each %fields) {
        $class->register_field($field, $definition);
    }
}

sub register_field {
    my ($class, $field, $options) = @_;

    # add dbic columns
    $class->add_columns($field => $options->{dbic});
    
    # add field to postable params
    if (exists $options->{edit}) {
        if ($options->{edit} eq 'postable' || $options->{edit} eq 'required') {
            $class->meta->add_around_method_modifier(postable_params => sub {
                my ($orig, $self) = @_;
                my $params = $orig->($self);
                push @$params, $field;
                return $params;
            });
            if ($options->{edit} eq 'required') {
                $class->meta->add_around_method_modifier(required_params => sub {
                    my ($orig, $self) = @_;
                    my $params = $orig->($self);
                    push @$params, $field;
                    return $params;
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
    
    # validation
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
                $describe->() if (defined $describe_options{current_user} && defined $describe_options{current_user}->is_admin);
            }
            elsif ($options->{view} eq 'private') {
                $describe->() if (defined $describe_options{current_user} && defined $self->can_use($describe_options{current_user}));
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
        $dup->$field($self->$field()) unless $options->{no_duplicate};
        return $dup;
    });
    
}

1;

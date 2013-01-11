package Wing::Role::Result::DateTimeField;

use Wing::Perl;
use Ouch;
use Moose::Role;
with 'Wing::Role::Result::Field';

=head1 NAME

Wing::Role::Result::DateTimeField - Inflate DB dates into Perl DateTime objects.

=head1 SYNOPSIS

 with 'Wing::Role::Result::DateTimeField';
 
 __PACKAGE__->wing_datetime_fields(
    last_login => {},
 );

=head1 DESCRIPTION

Using this role will allow you to inflate and deflate database date times into Perl L<DateTime>s automatically. Moreover, it will also handle the serialization and deserialization on web and rest interfaces. 
 
=cut

sub wing_datetime_fields {
    my ($class, %fields) = @_;
    while (my ($field, $definition) = each %fields) {
        $class->wing_datetime_field($field, $definition);
    }
}

sub wing_datetime_field {
    my ($object_class, $field, $options) = @_;

    my %dbic = ( data_type => 'datetime', is_nullable => 0 );
    if ($options->{set_on_create}) {
        $dbic{set_on_create} = 1;
    }
    if ($options->{set_on_update}) {
        $dbic{set_on_update} = 1;
    }
    $options->{dbic} = \%dbic;
    $options->{describe_method} = $field .'_mysql';
    $object_class->wing_field($field, $options);

    $object_class->meta->add_method( $field.'_mysql' => sub {
        my $self = shift;
        return Wing->to_mysql($self->$field);
    });

    $object_class->meta->add_after_method_modifier(wing_apply_fields => sub {
        my ($class) = @_;
        $class->meta->add_around_method_modifier($field => sub {
            if (scalar @_ == 3 && defined $_[2]) {
                my ($orig, $self, $proto_date) = @_;
                if (ref $proto_date eq 'DateTime') {
                    return $orig->($self, $proto_date);
                }
                else {
                    my $dt = eval { Wing->from_mysql($proto_date) };
                    if ($@) {
                        ouch 442, 'Invalid date/time: '.$proto_date;
                    }
                    $self->$orig($dt);
                }
            }
            return $_[0]->($_[1]);
        });
    });

}

1;

package Wing::Role::Result::DateTimeField;

use Wing::Perl;
use Ouch;
use Moose::Role;
with 'Wing::Role::Result::Field';

sub wing_datetime_fields {
    my ($class, %fields) = @_;
    while (my ($field, $definition) = each %fields) {
        $class->wing_datetime_field($field, $definition);
    }
}

sub wing_datetime_field {
    my ($class, $field, $options) = @_;

    my %dbic = ( data_type => 'datetime', is_nullable => 0 );
    if ($options->{set_on_create}) {
        $dbic{set_on_create} = 1;
    }
    if ($options->{set_on_update}) {
        $dbic{set_on_update} = 1;
    }
    $options->{dbic} = \%dbic;
    $options->{describe_method} = $field .'_rfc3339';
    $class->wing_field($field, $options);

    $class->meta->add_method( $field.'_rfc3339' => sub {
        my $self = shift;
        return Wing->to_RFC3339($self->$field);
    });

}

1;

package Wing::Role::Result::DateTimeField;

use Wing::Perl;
use Ouch;
use Moose::Role;
use DateTime::Format::RFC3339;
with 'Wing::Role::Result::Field';

sub register_datetime_fields {
    my ($class, %fields) = @_;
    while (my ($field, $definition) = each %fields) {
        $class->register_datetime_field($field, $definition);
    }
}

sub register_datetime_field {
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
    $class->register_field($field, $options);

    $class->meta->add_method( $field.'_rfc3339' => sub {
        my $self = shift;
        return DateTime::Format::RFC3339->new->format_datetime($self->$field);
    });

}

1;

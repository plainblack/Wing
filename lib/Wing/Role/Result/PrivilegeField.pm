package Wing::Role::Result::PrivilegeField;

use Wing::Perl;
use Ouch;
use Moose::Role;
with 'Wing::Role::Result::Field';

sub wing_privilege_fields {
    my ($class, %fields) = @_;
    while (my ($field, $definition) = each %fields) {
        $class->wing_privilege_field($field, $definition);
    }
}

sub wing_privilege_field {
    my ($class, $field, $options) = @_;

    my %dbic = (
        data_type       => 'tinyint',
        default_value   => 0,
        is_nullable     => 0,
    );
    $options->{dbic} = \%dbic;

    $options->{view} = 'private' unless exists $options->{view};
    $options->{edit} = 'admin' unless exists $options->{edit};
    $options->{_options} = { 0 => 'No', 1 => 'Yes'} unless exists $options->{_options};

    $class->wing_field($field, $options);
    
    my $is_method_name = 'is_'.$field;

    $class->meta->add_method($is_method_name => sub {
        my $self = shift;
        return $self->$field || $self->is_admin;
    });

    $class->meta->add_around_method_modifier( describe => sub {
        my ($orig, $self, %options) = @_;
        my $out = $orig->($self, %options);
        if ($options{include_private} && exists $options{current_user}) {
            $out->{$is_method_name} = $options{current_user}->$is_method_name;
        }
        return $out;
    });

    $class->meta->add_method('verify_is_'. $field => sub {
        my $self = shift;
        unless ($self->$is_method_name) {
            ouch 450, 'You do not have the privileges necessary to do that.';
        }
        return $self;
    });
}

1;

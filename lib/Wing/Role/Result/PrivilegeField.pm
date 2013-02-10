package Wing::Role::Result::PrivilegeField;

use Wing::Perl;
use Ouch;
use Moose::Role;
with 'Wing::Role::Result::Field';

=head1 NAME

Wing::Role::Result::PrivilegeField - Add special privileges to users.

=head1 SYNOPSIS

 with 'Wing::Role::Result::PrivilegeField';

 __PACKAGE__->wing_privilege_fields(
    approved_for_invoice    => {
        dbic => {
            data_type       => 'tinyint',
            default_value   => 0,
            is_nullable     => 0,
        },
        view    => 'private',
        edit    => 'admin',
        _options=> { 0 => 'No', 1 => 'Yes'},
    }, 
    pizza_manager           => {}, # can just leave this blank and it will default to the above example
 );

=head1 DESCRIPTION

Use this role in your user object to assign special privileges to each user.

=head1 ADDS

=head2 Helpers

=over

=item wing_privilege_field ( field_name, options)

Adds a single privilege field to your object.

=over

=item field_name

The name of the field you want to add and tie the privilege to.

=item options

A hash reference of field creation options. See L<Wing::Role::Result::Field> for more info.

=back

=item wing_privilege_fields ( fields )

Exactly the same as C<wing_privilege_field> but allows you to pass in a hash of fields all at once. 

=back

 
=head2 Fields

=over

=item C<field_name>

Whatever field you add using C<wing_privilege_fields>


=head2 Methods

=over

=item is_C<field_name>

An alias for C<field_name>.

=item verify_is_C<field_name>.

Same is_C<field_name> but L<Ouch>es a 450 error if false.

=back


=cut

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
    $options->{options} = [ 0, 1 ] unless exists $options->{options};
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
        if ($options{include_private} && exists $options{current_user} && defined $options{current_user}) {
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

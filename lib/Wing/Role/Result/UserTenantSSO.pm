with 'Wing::Role::Result::UserTenantSSO';

use Wing::Perl;
use Moose::Role;
with 'Wing::Role::Result::Field';

requires 'syncable_fields';

=head1 NAME

Wing::Role::Result::UserTenantSSO - Allowing tenant SSO for Wing users

=head1 SYNOPSIS

 with 'Wing::Role;:Result::User';
 with 'Wing::Role::Result::UserTenantSSO';
 
=head1 DESCRIPTION

This role extends your User objects to include the fields necessary to make tenant SSO work on the client (tenant) side.

=cut

before wing_finalize_class => sub {
    my ($class) = @_;
    $class->wing_fields(
        master_user_id          => {
            dbic    => { data_type => 'varchar', size => 30, is_nullable => 0 },
            view    => 'private',
            edit    => 'unique',
        },
};

sub sync_with_remote_data {
    my $self = shift;
    my $data = shift;
    foreach my $field (@{ $self->syncable_fields } ) {
        $self->$field($data->$field);
    }
}

1;

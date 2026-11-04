package Wing::Role::Result::UserTenantSSO;

use Wing::Perl;
use Moose::Role;
with 'Wing::Role::Result::Field';

=head1 NAME

Wing::Role::Result::UserTenantSSO - Allowing tenant SSO for Wing users

=head1 SYNOPSIS

 with 'Wing::Role::Result::User';
 with 'Wing::Role::Result::UserTenantSSO';

 use constant syncable_fields qw/email real_name username password password_type password_salt use_as_display_name/;
 
=head1 DESCRIPTION

This role extends your User objects to include the fields necessary to make tenant SSO work on the client (tenant) side.

C<master_user_id> is nullable for tenant-local accounts; linked accounts store
their owner's user ID. Existing applications must generate and apply their own
schema upgrade to allow NULL before creating tenant-local accounts. Upgrading
Wing alone does not change an application's existing tables.
Only internal synchronization sets this link; posted account fields cannot set it.

=cut

before wing_finalize_class => sub {
    my ($class) = @_;
    $class->wing_fields(
        master_user_id          => {
            dbic    => { data_type => 'varchar', size => 36, is_nullable => 1 },
            view    => 'private',
            indexed => 'unique',
            skip_unique_if_null => 1,
        },
    );
};

around describe => sub {
    my ($orig, $self, %options) = @_;
    my $out = $self->$orig(%options);
    $out->{tenant_user} = $self->master_user_id ? 1 : 0;
    return $out;
};

sub sync_with_remote_data {
    my $self = shift;
    my $data = shift;
    my @syncable_fields = @_;
    foreach my $field ( @syncable_fields ) {
        $self->$field($data->{$field});
    }
}

1;

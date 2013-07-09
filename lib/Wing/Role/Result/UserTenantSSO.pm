with 'Wing::Role::Result::UserTenantSSO';

use Wing::Perl;
use Moose::Role;
with 'Wing::Role::Result::Field';

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

1;

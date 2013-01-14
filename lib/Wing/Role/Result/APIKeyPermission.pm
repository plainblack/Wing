package Wing::Role::Result::APIKeyPermission;

use Wing::Perl;
use Wing;
use Ouch;
use Moose::Role;
with 'Wing::Role::Result::Field';
with 'Wing::Role::Result::UserControlled';
with 'Wing::Role::Result::Parent';


=head1 NAME

Wing::Role::Result::APIKeyPermission - The basis of Wing API service key permissions.

=head1 SYNOPSIS

 with 'Wing::Role::Result::APIKeyPermission';
 
=head1 DESCRIPTION

This is a foundational role for the required APIKeyPermission class. API Key Permissions are used in Wing to grant privileges to third-party applications.

=head1 REQUIREMENTS

All Wing Apps need to have a class called AppName::DB::Result::APIKeyPermission that uses this role as a starting point.

=head1 ADDS

=head2 Fields

=over

=item permission

The name of a permission being granted to this API key. 

=back

=head2 Parents

=over

=item apikey

A relationship to a L<Wing::Role::Result::APIKey> enabled object.

=back

=cut

before wing_finalize_class => sub {
    my ($class) = @_;
    $class->wing_field(
        permission                  => {
            dbic                => { data_type => 'varchar', size => 30, is_nullable => 0 },
            view                => 'private',
            edit                => 'postable',
            options             => Wing->config->get('api_key_permissions'),
        }
    );
    my $namespace = $class;
    $namespace =~ s/^(\w+)\:.*$/$1/;
    $class->wing_parent(
        apikey   => {
            view                => 'parent',
            edit                => 'required',
            related_class       => $namespace.'::DB::Result::APIKey',
            related_id          => 'api_key_id',
        }
    );
};

after sqlt_deploy_hook => sub {
    my ($self, $sqlt_table) = @_;
    $sqlt_table->add_index(name => 'idx_apikey_user', fields => ['api_key_id','user_id']);
};

1;

package Wing::Role::Result::APIKey;

use Wing::Perl;
use Ouch;
use Moose::Role;
with 'Wing::Role::Result::Field';
with 'Wing::Role::Result::UserControlled';
with 'Wing::Role::Result::Child';

=head1 NAME

Wing::Role::Result::APIKey - The basis of Wing API service keys.

=head1 SYNOPSIS

 with 'Wing::Role::Result::APIKey';
 
=head1 DESCRIPTION

This is a foundational role for the required APIKey class. API Keys are used in Wing to grant access to third-party applications.

=head1 REQUIREMENTS

All Wing Apps need to have a class called AppName::DB::Result::APIKey that uses this role as a starting point.

=head1 ADDS

=head2 Fields

=over

=item name

The name of the application, person, or service that will be using this key.

=item uri

An optional URL of the application, person, or service using the key.

=item reason

The reason this key was created.

=item private_key

The private side of this key which can be used as an encryption key or a password.

=back

=head2 Children

=over

=item permissions

A relationship to a L<Wing::Role::Result::APIKeyPermmission> enabled object.

=back

=cut

before wing_finalize_class => sub {
    my ($class) = @_;
    $class->wing_fields(
        name    => {
            dbic    => { data_type => 'varchar', size => 30, is_nullable => 0 },
            view    => 'public',
            edit    => 'unique',
        },
        uri                     => {
            dbic    => { data_type => 'varchar', size => 255, is_nullable => 1 },
            view    => 'public',
            edit    => 'postable',
        },
        reason                  => {
            dbic    => { data_type => 'varchar', size => 255, is_nullable => 1 },
            view    => 'private',
            edit    => 'postable',
        },
        private_key             => {
            dbic    => { data_type => 'char', size => '36', is_nullable => 1 },
            view    => 'private',
        },
    );

    my $namespace = $class;
    $namespace =~ s/^(\w+)\:.*$/$1/;
    $class->wing_child(
        permissions   => {
            view                => 'private',
            related_class       => $namespace.'::DB::Result::APIKeyPermission',
            related_id          => 'api_key_id',
        }
    );

};

1;

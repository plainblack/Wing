package Wing::Role::Result::FacebookAuthUser;

use Wing::Perl;
use Moose::Role;
with 'Wing::Role::Result::Field';


=head1 NAME

Wing::Role::Result::FacebookAuthUser - Allow users to authenticate against Facebook.

=head1 SYNOPSIS

 with 'Wing::Role::Result::FacebookAuthUser';
 
=head1 DESCRIPTION

If you add this to your user class it will create the fields necessary for a user to authenticate against Facebook.

=head1 ADDS

=head2 Fields

=over

=item facebook_uid 

The user's unique id on Facebook.

=item facebook_token

The user's authentication token on Facebook if we need to authenticate to Facebook on their behalf.

=back

=cut

before wing_finalize_class => sub {
    my ($class) = @_;
    $class->wing_fields(
        facebook_uid            => {
            dbic                => { data_type => 'bigint', is_nullable => 1 },
            view                => 'private',
            indexed             => 1,
            edit                => 'postable',
        },
        facebook_token          => {
            dbic                => { data_type => 'varchar', size => 100, is_nullable => 1 },
            view                => 'private',
        },
    );
};

1;

package Wing::Role::Result::AnybodyControlled;

use Wing::Perl;
use Ouch;
use Moose::Role;
with 'Wing::Role::Result::Field';
with 'Wing::Role::Result::Parent';

=head1 NAME

Wing::Role::Result::AnybodyControlled - Make your Wing objects controllable by users and visitors.

=head1 SYNOPSIS

 with 'Wing::Role::Result::AnybodyControlled';

=head1 DESCRIPTION

Use this role in your object when you want to allow visitor created content on your site. It's good for comments, suggestions, etc.

=head1 ADDS

=head2 Fields

=over

=item tracer

A GUID that is attached as a cookie to visitors of the site and associates those visitors with the object at creation time.

=item ipaddress

The IP address of the user at object creation time.
 
=item useragent

The browser user agent at object creation time.

=back

=head2 Parents

=over

=item user

A reference to a user object.

=back

=cut


before wing_finalize_class => sub {
    my ($class) = @_;
    $class->wing_fields(
        tracer => {
            dbic        => { data_type => 'char', size => 36, is_nullable => 0 },
            view        => 'public',
            edit        => 'postable',
            indexed     => 1,
        },
        ipaddress => {
            dbic        => { data_type => 'varchar', size => 128, is_nullable => 0 },
            view        => 'public',
            edit        => 'postable',
            indexed     => 1,
        },
        useragent => {
            dbic        => { data_type => 'varchar', size => 255, is_nullable => 0 },
            view        => 'public',
            edit        => 'postable',
            indexed     => 1,
        },
    );    
    my $namespace = $class;
    $namespace =~ s/^(\w+)\:.*$/$1/;
    $class->wing_parent(
        user    => {
            view        => 'public',
            edit        => 'postable',
            related_class   => $namespace.'::DB::Result::User',
        }
    );
};

around can_edit => sub {
    my ($orig, $self, $user, $tracer) = @_;
    if ($self->user_id) {
        return 1 if $self->user->can_edit($user);
    }
    elsif ($self->tracer && $tracer) {
        return 1 if $self->tracer eq $tracer;
    }
    return $orig->($self, $user);
};

1;

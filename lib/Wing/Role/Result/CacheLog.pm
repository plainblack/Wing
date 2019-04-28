package Wing::Role::Result::CacheLog;

use Wing::Perl;
use Ouch;
use Moose::Role;
use Time::HiRes;
with 'Wing::Role::Result::Field';

=head1 NAME

Wing::Role::Result::CacheLog - Logging of Wing's cache system.

=head1 SYNOPSIS

 with 'Wing::Role::Result::CacheLog';

=head1 DESCRIPTION

This is a foundational role for the CacheLog class. The CacheLog can be used in debugging cache problems. It is entirely optional whether you create a CacheLog class in your app.

There is no UI for this log. You'll need to look in the database to read the data.

=head1 REQUIREMENTS

You'll need to create a class called AppName::DB::Result::CacheLog that uses this role as a starting point. And then you'll add a directive called C<cachelog> set to C<db> in your wing.conf.

=head1 ADDS

=head2 Fields

=over

=item action

The action taken. Can be one of C<get>, C<set>, or C<remove>.

=item name

The name of the cache key.

=item value

The stringified value stored with the key.

=item process_id

The system process id that took these actions. Can be useful to see when a group of cache requests happened in the same operation.

=item microseconds

A high resolution epoch time for setting of cache. It takes the format of seconds.microseconds from January 1, 1970.

=back

=cut

before wing_finalize_class => sub {
    my ($class) = @_;
    $class->wing_fields(
        action    => {
            dbic    => { data_type => 'varchar', size => 6, is_nullable => 0 },
        },
        name                     => {
            dbic    => { data_type => 'varchar', size => 255, is_nullable => 1 },
        },
        value                  => {
            dbic    => { data_type => 'mediumblob', is_nullable => 1 },
        },
        process_id             => {
            dbic    => { data_type => 'int', is_nullable => 0 },
        },
        microseconds             => {
            dbic    => { data_type => 'bigint', is_nullable => 0 },
        },
    );
};

before insert => sub {
    my $self = shift;
    $self->microseconds(Time::HiRes::time() * 1_000_000);
};

1;

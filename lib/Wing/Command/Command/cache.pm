package Wing::Command::Command::cache;

use Wing;
use Wing::Perl;
use Wing::Command -command;
use Data::Dumper;

sub abstract { 'manipulate items in the cache' }

sub usage_desc { 'Manipulate items in the cache.' }

sub opt_spec {
    return (
      [ 'get=s', 'Get an item from cache with key.'],
      [ 'remove=s', 'Remove cache key.'],
      [ 'set=s', 'Set an item in cache with key.'],
      [ 'value=s', 'Use with --set to set the value of the key.'],
      [ 'ttl=i', 'Use with --set to set the cache time to live.'],
    );
}

sub validate_args {
    my ($self, $opt, $args) = @_;
    # no args allowed but options!
    $self->usage_error("No args allowed, only options.") if @$args;
}

sub execute {
    my ($self, $opt, $args) = @_;

    if (exists $opt->{remove}) {
        Wing->cache->remove($opt->{remove});
        say $opt->{remove}." key has been removed.";
    }

    if (exists $opt->{set}) {
        Wing->cache->set($opt->{set}, $opt->{value}, $opt->{ttl});
        say $opt->{set}." has been set to ".$opt->{value};
    }

    if (exists $opt->{get}) {
        my $value = Wing->cache->get($opt->{get});
        print "The value of ".$opt->{get}." is: ";
        if (ref $value) {
            say Dumper $value;
        }
        else {
            say $value;
        }
    }
}

1;

=head1 NAME

wing cache - manipulate items in cache 

=head1 SYNOPSIS

 wing cache --remove=key

=head1 DESCRIPTION

Using this command you can manipulate items in the cache.

=head1 OPTIONS

=over

=item B<--remove=KEY>

This option will remove a cache key from the cache.

=item B<--get=KEY>

This option will display the value of a key in the cache.

=item B<--set=KEY>

This option will set the value of a key in the cache.

=item B<--value=VALUE>

This option should be used with --set to set the value of C<KEY>.

=item B<--ttl=TTL>

This option should be used with --set to determine how long an item should live in the cache.

=back

=head1 AUTHOR

Copyright 2015 Plain Black Corporation.

=cut

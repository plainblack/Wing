package Wing::Perl;

=head1 NAME

Wing::Perl - Standardize what Perl configuration Wing uses.


=head1 SYNOPSIS

 use Wing::Perl;

=cut

use 5.010_000;

use strict;
use warnings;

use mro     ();
use feature ();
use utf8    ();

sub import {
    warnings->import();
    warnings->unimport( 'uninitialized' );
    strict->import();
    feature->import( ':5.10' );
    mro::set_mro( scalar caller(), 'c3' );
    utf8->import();
}

1;

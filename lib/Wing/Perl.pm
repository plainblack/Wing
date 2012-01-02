package Wing::Perl;

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

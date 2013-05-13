package TestWing::Wingman::HelloWorld;

use Moose;
with 'Wingman::Role::Plugin';

sub run {
    return "Hello World";
}


1;

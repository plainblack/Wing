package TestWing::Wingman::EchoJson;

use strict;
use JSON;
use Moose;
with 'Wingman::Role::Plugin';

sub run {
    my ($self, $args) = @_;
    return to_json($args);
}

1;



package TestWing::Wingman::EchoJson;

use strict;
use JSON;
use Moose;
with 'Wingman::Role::Plugin';

sub run {
    my ($self, $job, $args) = @_;
    my $json = to_json($args);
    $job->delete;
    return $json;
}

1;



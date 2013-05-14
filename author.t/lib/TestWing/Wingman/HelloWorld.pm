package TestWing::Wingman::HelloWorld;

use Moose;
with 'Wingman::Role::Plugin';

sub run {
    my ($self, $job) = @_;
    $job->delete;
    return "Hello World";
}


1;

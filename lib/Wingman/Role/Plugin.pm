package Wingman::Role::Plugin;

=head1 NAME

Wingman::Role::Plugin - A required component for all Wingman plugins.

=head1 SYNOPSIS

 with 'Wingman::Role::Plugin';

=head1 DESCRIPTION

Include this in all your plugins. See the B<Plugin Development> section of L<Wingman> for details.

=cut

use Moose::Role;

requires 'run';

1;

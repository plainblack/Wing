package Wing::Command::Command::guid;

use Wing;
use Wing::Perl;
use Wing::Command -command;
use Data::GUID;
use Ouch;

sub abstract { 'generate GUIDs' }

sub usage_desc { 'Gives you a GUID instead of having to make one up' }

sub description {'Examples:
wing guid

'}

sub opt_spec {
    return ();
}

sub validate_args {
    my ($self, $opt, $args) = @_;
    # no args allowed but options!
    $self->usage_error("No args allowed, only options.") if @$args;
}

sub execute {
    my ($self, $opt, $args) = @_;
    say Data::GUID->guid_string;
}

1;

=head1 NAME

wing guid - Generate GUID's on the command line so you don't have to make them up.

=head1 SYNOPSIS

 wing guid

=head1 DESCRIPTION

Just a way to make you a GUID so you can copy/paste it where needed, for tests, new config file entires, or whatever.

=head1 AUTHOR

Copyright 2012-2013 Plain Black Corporation.

=cut

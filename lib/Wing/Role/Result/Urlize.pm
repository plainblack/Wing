package Wing::Role::Result::Urlize;

use Wing::Perl;
use Moose::Role;
use Ouch;

=head1 NAME

Wing::Role::Result::Urlize - Convert names, titles into URI safe strings

=head1 SYNOPSIS

 with 'Wing::Role::Result::Urlize';

 $self->urlize('Some odd looking thing');

=head1 DESCRIPTION

Create an automatically defined URL based on a string. The uri_part is NOT guaranteed to be unique, you must ensure this yourself. If the name cannot be turned into a uri_part for some reason it will ouch 443.

=head1 REQUIREMENTS

=head1 ADDS

=head2 methods

=over

=item urlize ($string)

Create the URL safe string based on the input

=back

=cut

sub urlize {
    my ($self, $string) = @_;
    my $uri_part = lc($string);
    $uri_part =~ s{^\s+}{};          # remove leading whitespace
    $uri_part =~ s{\s+$}{};          # remove trailing whitespace
    $uri_part =~ s{^/+}{};           # remove leading slashes
    $uri_part =~ s{/+$}{};           # remove trailing slashes
    $uri_part =~ s{[^\w/:.-]+}{-}g;  # replace anything aside from word or other allowed characters with dashes
    $uri_part =~ tr{/-}{-}s;        # replace multiple slashes and dashes with single dashes.
    if ($uri_part =~ m/^\s+$/) {
        ouch 443, 'That name is not available because it contains too few word characters.', 'name';
    }
    return $uri_part;
}

1;

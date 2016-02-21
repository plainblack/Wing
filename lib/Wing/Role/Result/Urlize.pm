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

Create an automatically defined URL based on a string. If the name cannot be turned into a uri_part for some reason it will ouch 443.

=head1 REQUIREMENTS

=head1 ADDS

=head2 Methods

=head3 urlize (string)

Create the URL safe string based on the input. The uri_part returned is NOT guaranteed to be unique, you must ensure this yourself, or use the C<set_uri_part> method.

=over

=item string

The string to convert into a safe url.

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

=head3 set_uri_part ( name, class )

Sets the C<uri_part> field. Note that your class or role must create a C<uri_part> field, as this class does not add it.

=over

=item name

This string will be passed through L<Wing::Role::Result::Urlize> and then checked for uniqueness to autogenerate a URI Part.

=item class

The name of the class to check for duplicates of uri_part. Can be a full class like C<MyApp::DB::Result::MyClass> or the shortened C<MyClass> version.

=back

=cut

sub set_uri_part {
    my ($self, $name, $class) = @_;
    if ($name) {
        # convert into a url
        my $uri_part = $self->urlize($name);

        # deal with duplicates
        my $objects = $self->result_source->schema->resultset($class);
        if ($self->in_storage) {
            $objects = $objects->search({ id => { '!=' => $self->id }});
        }
        my $counter = '';
        my $shrink = sub {
            my $total_length = length($uri_part) + length($counter);
            if ($total_length > 60) {
                my $overage = $total_length - 58;
                $uri_part = substr($uri_part, 0, $total_length - $overage);
            }
        };
        $shrink->();
        while ($objects->search({ uri_part => $uri_part.$counter })->count) {
            $counter++;
            $shrink->();
        }
        $uri_part .= $counter;
        
        # yay, we're ready
        $self->uri_part($uri_part);
    }
}

1;

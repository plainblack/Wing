package Wing::Util;
use List::MoreUtils qw(any);
use Ouch;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(randint random_element commify is_in generate_trigram_from_string trigram_match_against);

=head1 NAME

=head1 SYNOPSIS

 use Wing::Util qw(randint random_element commify is_in generate_trigram_from_string trigram_match_against); # or whichever utilities you need

=head1 DESCRIPTION

A collection of useful utilities that don't belong in any other place.

=head1 FUNCTIONS

=head2 randint( low, high )

Return a random number between C<low> and C<high> (inclusive).

=over

=item low

An integer between 0 and C<high>.

=item high

An integer between C<low> and infinity.

=back

=cut

sub randint {
    my ($low, $high) = @_;
    $low = 0 unless defined $low;
    $high = 1 unless defined $high;
    ($low, $high) = ($high,$low) if $low > $high;
    return int($low + int( rand( $high - $low + 1 ) ));
}

=head2 random_element( array_ref )

Returns a random element from an array reference.

=over

=item array_ref

An array reference of possible values.

=back

=cut

sub random_element {
    my ($list) = @_;
    return $list->[randint(0, scalar(@{$list} -1 ))];
}

=head2 commify( number )

Adds commas to a number at every 3rd digit.

 commify(1000); # 1,000

=over

=item number

The number to be commified. Can be a decimal or an integer.

=back

=cut

sub commify {
    my $text = reverse $_[0];
    $text =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
    return scalar reverse $text;
}

=head2 is_in( string, array_ref )

Returns 1 if C<string> is in C<array_ref>. Otherwise returns 0.

=over

=item string

The value to search for in the C<array_ref>.

=item array_ref

The array reference to search to find the C<string>.

=back

=cut

sub is_in {
    my ($key, $array_ref) = @_;
    ouch(500, 'Needs array ref') unless ref $array_ref eq 'ARRAY';
    return any {$_ eq $key} @{$array_ref};
}

=head2 generate_trigram_from_string( string )

Generates a trigram from a string. Useful for creating or searching tri-grams (a type of n-gram). See L<Wing::Role::Result::Trigram> for details.

 generate_trigram_from_string('Wing'); # 'Win ing'

=over

=item string

The string to turn into a trigram.

=back

=cut

sub generate_trigram_from_string {
    my ($string) = @_;
    $string =~ s/^\s+|\s+$//gm;
    $string =~ s/\s+/_/gm;
    $string =~ s/[\W]+//gm;
    # need a minimum of 3 characters to form a trigram
    if (length $string == 1) {
        $string .= '__';
    }
    elsif (length $string == 2) {
        $string .= '_';
    }
    my @list_of_trigrams;
    while ($string =~ /^(...)/gm) {
        push @list_of_trigrams, $1;
        $string = substr($string, 1);
    }
    return join ' ', @list_of_trigrams;
}

=head2 trigram_match_against( string, [dbix_slot_prefix] )

Returns an array reference reference that can be used as a L<DBIx::Class::ResultSet> search literal. Works as a class method or object method.

 my $rs = Wing->db->resultset('SomeClass')->search({ -or => [ MyProject::DB::Result::SomeClass->trigram_match_against($query_string) ]});

=over

=item string

The string to search the trigram for.

=item dbix_slot_prefix

Optional. If not specified, then it defaults to C<me>. This is used as an alias for a table name.

=back

=cut

sub trigram_match_against {
    my ($string, $dbix_slot_prefix) = @_;
    $dbix_slot_prefix //= 'me';
    return \['match('.$dbix_slot_prefix.'.trigram_search) against(? in boolean mode)',generate_trigram_from_string($string)];
}

1;


package Wing::Util;
use List::MoreUtils qw(any);

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
    randint
    random_element
    commify
    is_in
    );


# Return a random integer between $low and $high inclusive
sub randint {
    my ($low, $high) = @_;
    $low = 0 unless defined $low;
    $high = 1 unless defined $high;
    ($low, $high) = ($high,$low) if $low > $high;
    return int($low + int( rand( $high - $low + 1 ) ));
}

sub random_element {
    my ($list) = @_;
    return $list->[randint(0, scalar(@{$list} -1 ))];
}

sub commify {
    my $text = reverse $_[0];
    $text =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
    return scalar reverse $text;
}

sub is_in {
    my ($key, $array_ref) = @_;
    return any {$_ eq $key}, @{$array_ref};
}

1;


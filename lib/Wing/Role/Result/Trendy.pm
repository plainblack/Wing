package Wing::Role::Result::Trendy;

use Wing::Perl;
use Ouch;
use Moose::Role;
use Wing::TrendsLogger;

=head1 NAME

Wing::Role::Result::Trendy

=head1 DESCRIPTION

A role wrapper around L<Wing::TrendsLogger>. Use to easily log trends from any class.

=head1 METHOD

=head2 log_trend(params)

Log a trend.

=over

=item params

The same params as L<log_trend/Trends::Logger>.

=back

=cut

sub log_trend {
    my $self = shift;
    Wing::TrendsLogger::log_trend(@_);
}

1;

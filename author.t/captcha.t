use lib '/data/Wing/author.t/lib', '/data/Wing/lib';
use Wing::Perl;
use Test::More;

use_ok('Wing::Captcha');

my $riddles = Wing::Captcha::build_riddles();

foreach my $riddle (keys %{$riddles}) {
	diag $riddle.' = '.$riddles->{$riddle};
}

done_testing();

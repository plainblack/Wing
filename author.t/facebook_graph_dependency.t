use strict;
use warnings;
use FindBin;
use Test::More;

my $script = "$FindBin::Bin/../bin/setup/03_install_perl_modules.sh";
open my $input, '<', $script or die "Cannot read Perl dependency setup script: $!";
my @dependencies = map { /^\s*([A-Za-z][A-Za-z0-9_:]*)\s*\\?\s*$/ ? $1 : () } <$input>;
my %dependencies = map { $_ => 1 } @dependencies;

ok !$dependencies{'Facebook::Graph'}, 'setup does not install the discontinued Facebook::Graph package';
ok $dependencies{'Facebook::OpenGraph'}, 'the existing Facebook integration keeps its OpenGraph dependency';
ok $dependencies{'Data::OpenGraph'}, 'generic OpenGraph metadata parsing keeps its dependency';

done_testing;

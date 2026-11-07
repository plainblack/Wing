use strict;
use warnings;
use FindBin;
use Test::More;

my $runner = "$FindBin::Bin/run.pl";
for my $args (['--slice', '3'], ['--slice', 'a/8'], ['--slice', '9/8'], ['--slice', '1/8', 'author.t/user.t'], [], ['author.t/TESTME']) {
    my $output = `"$^X" "$runner" @$args 2>&1`;
    is $? >> 8, 2, "runner refuses '@$args' before touching services";
    like $output, qr/Use: perl author\.t\/run\.pl/, "runner explains its usage for '@$args'";
}
done_testing;

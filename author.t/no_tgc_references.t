use strict;
use warnings;
use FindBin;
use Test::More;

# Wing is shared by applications, so nothing outside its change history may name TGC.
my $root = "$FindBin::Bin/..";
my @hits = `git -C '$root' grep -I -n -i tgc -- . ':!CHANGES.txt' ':!author.t/no_tgc_references.t'`;
is $? >> 8, 1, 'git grep ran and found no match' or diag @hits;

done_testing;

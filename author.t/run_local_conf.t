use strict;
use warnings;
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use JSON;
use Test::More;

# The runner reads etc/local.conf next to its own author.t, so give a copy of it a scratch checkout.
my $root = tempdir(CLEANUP => 1);
make_path("$root/author.t/etc", "$root/etc");
copy("$FindBin::Bin/$_", "$root/author.t/$_") or die "Cannot copy author.t/$_: $!\n" for qw(run.pl status.t etc/test.conf);
sub run_runner { my $output = `"$^X" "$root/author.t/run.pl" "$root/author.t/status.t" 2>&1`; return ($?, $output) }

my ($status, $output) = run_runner();
isnt $status, 0, 'runner fails without etc/local.conf';
like $output, qr/\Q$root\E\/etc\/local\.conf.*TESTING\.md/s, 'runner names the missing file and where it is documented';
unlike $output, qr/^ok /m, 'runner runs no tests without etc/local.conf';

sub write_local { open my $file, '>', "$root/etc/local.conf" or die "Cannot write $root/etc/local.conf: $!\n"; print $file encode_json({db => [shift, 'testwing', 'testwing']}) }
my $socket = "$root/no-mysql-here.sock";

# The runner drops and recreates the database it names, so it must be the test database and nothing else.
for my $dsn ("DBI:mysql:database=wing;mysql_socket=$socket", "DBI:mysql:database=testwing-dev;mysql_socket=$socket") {
    write_local($dsn);
    ($status, $output) = run_runner();
    isnt $status, 0, "runner refuses $dsn";
    like $output, qr/\Q$root\E\/etc\/local\.conf must start DBI:mysql:database=testwing/, "runner explains why it refuses $dsn";
    unlike $output, qr/\Q$socket\E/, "runner does not connect to $dsn";
}

write_local("DBI:mysql:database=testwing;mysql_socket=$socket");
($status, $output) = run_runner();
isnt $status, 0, 'runner fails when the dev MySQL is unreachable';
like $output, qr/\Q$socket\E/, 'runner connects where etc/local.conf says';
like $output, qr/\Q$root\E\/etc\/local\.conf.*TESTING\.md/s, 'runner tells the human which file to fix';
unlike $output, qr/^ok /m, 'runner runs no tests when MySQL is unreachable';
done_testing;

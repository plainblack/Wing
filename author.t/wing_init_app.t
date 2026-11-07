use strict;
use warnings;
use FindBin;
use File::Find;
use File::Temp qw(tempdir);
use Test::More;

my $source = "$FindBin::Bin/../var/init/var/mkits";
my $root = tempdir(CLEANUP => 1);
my $output = `"$^X" "$FindBin::Bin/../bin/wing_init_app.pl" --app=Example --root="$root" 2>&1`;
is $? >> 8, 0, 'wing_init_app.pl creates the app' or diag $output;

my @kits = map { m{/([^/]+)$} } glob "$source/*.mkit";
ok grep({ $_ eq 'stuck_wingman_job.mkit' } @kits), 'Wing ships the stuck_wingman_job mail kit';

# Mail kits are runtime TT templates, so a new app gets them byte for byte.
find({ no_chdir => 1, wanted => sub {
    return unless -f;
    (my $relative = $File::Find::name) =~ s{^\Q$source\E/}{};
    my $copy = "$root/Example/var/mkits/$relative";
    ok -f $copy, "$relative is copied" or return;
    is slurp($copy), slurp($File::Find::name), "$relative keeps its template tags";
} }, $source);

sub slurp {
    open my $fh, '<', shift or die $!;
    local $/;
    return <$fh>;
}

done_testing;

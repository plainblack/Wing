use strict;
use warnings;
use Cwd qw(getcwd);
use FindBin;
use File::Find;
use File::Glob ':bsd_glob';
use File::Temp qw(tempdir);
use Config::JSON;
use Test::More;

my $source = "$FindBin::Bin/../var/init/var/mkits";
my $script = "$FindBin::Bin/../bin/wing_init_app.pl";
my $tmp = tempdir(CLEANUP => 1);
my $cwd = getcwd();
chdir $tmp or die "Cannot enter $tmp: $!";
$tmp = getcwd();
# a relative root with a space checks that paths are made absolute and not split
my $output = `"$^X" "$script" --app=Example "--root=My Apps" 2>&1`;
chdir $cwd or die "Cannot return to $cwd: $!";
is $?, 0, 'wing_init_app.pl creates the app' or diag $output;
my $app = "$tmp/My Apps/Example";

my $config = Config::JSON->new("$app/etc/wing.conf");
is $config->get('mkits'), "$app/var/mkits/", 'wing.conf names the mail kits by absolute path';
ok -x "$app/bin/web.psgi", 'bin scripts are executable';

my @kits = map { m{/([^/]+)$} } glob "$source/*.mkit";
ok grep({ $_ eq 'stuck_wingman_job.mkit' } @kits), 'Wing ships the stuck_wingman_job mail kit';

# Mail kits are runtime TT templates, so a new app gets them byte for byte.
find({ no_chdir => 1, wanted => sub {
    return unless -f;
    (my $relative = $File::Find::name) =~ s{^\Q$source\E/}{};
    my $copy = "$app/var/mkits/$relative";
    ok -f $copy, "$relative is copied" or return;
    is slurp($copy), slurp($File::Find::name), "$relative keeps its template tags";
} }, $source);

sub slurp {
    my $path = shift;
    open my $fh, '<', $path or die "Cannot read $path: $!";
    local $/;
    return <$fh>;
}

done_testing;

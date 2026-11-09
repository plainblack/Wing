use strict;
use warnings;
use Cwd qw(realpath);
use Beanstalk::Client;
use DBI;
use File::Glob qw(bsd_glob);
use File::Path qw(remove_tree);
use File::Temp qw(tempdir);
use FindBin;
use Getopt::Long;
use JSON;
use Config::JSON;
use POSIX qw(setpgid _exit);

# Runs Wing author tests against the running dev MySQL named in etc/local.conf and the Beanstalkd named in author.t/etc/test.conf.
my $root = realpath("$FindBin::Bin/..");
my $usage = "Use: perl author.t/run.pl author.t/<test>.t ... | --slice k/count (1 <= k <= count)\n";
sub refuse { print STDERR $_[0], $usage; exit 2 }

GetOptions('slice=s' => \my $slice) or refuse('');
my @available = sort(bsd_glob("$root/author.t/*.t"));
my @tests;
if (defined $slice) {
    my ($index, $count) = $slice =~ m{^(\d+)/(\d+)$};
    refuse("Slice must be k/count.\n") unless $count && $index >= 1 && $index <= $count && !@ARGV;
    @tests = @available[grep { $_ % $count == $index - 1 } 0 .. $#available];
}
else {
    refuse("Name at least one author test.\n") unless @ARGV;
    my %known = map { $_ => 1 } @available;
    @tests = map { realpath($_) // '' } @ARGV;
    refuse("Only checked-in author.t/*.t tests may run.\n") if grep { !$known{$_} } @tests;
}

my $config = Config::JSON->new("$root/author.t/etc/test.conf")->config;
my $local = "$root/etc/local.conf";
-f $local or die "Cannot find $local. Create it with a db entry for your running dev MySQL; see TESTING.md.\n";
$config->{db} = Config::JSON->new($local)->get('db') or die "$local needs a db entry for your running dev MySQL; see TESTING.md.\n";
my ($dsn, $user, $password) = @{$config->{db}};
my ($prefix, $database, $suffix) = $dsn =~ /^(.*database=)(\w+)(.*)$/
    or die "The db entry in $local must name its database, like DBI:mysql:database=testwing; see TESTING.md.\n";
# Tenant databases live on the same dev MySQL.
@{$config->{tenants}{db_driver}}{qw(prefix suffix)} = ($prefix, $suffix);
my $dbh = DBI->connect($dsn, $user, $password, {RaiseError => 0, PrintError => 0})
    or die "Cannot reach the dev MySQL named in $local: $DBI::errstr\nStart MySQL, or fix the db entry in $local; see TESTING.md.\n";
$dbh->{RaiseError} = 1;
# Runs share one database and broker, so take turns; MySQL releases the lock if a run dies.
my $lock = "$database author tests";
unless ($dbh->selectrow_array('SELECT GET_LOCK(?, 0)', undef, $lock)) {
    print STDERR "Waiting for another author test run using $database to finish.\n";
    $dbh->selectrow_array('SELECT GET_LOCK(?, -1)', undef, $lock);
}
sub drop_extra_databases {
    # Tests may only create databases named ${database}_*, which the test account is granted.
    my $pattern = $database =~ s/_/\\_/gr;
    $dbh->do('DROP DATABASE '.$dbh->quote_identifier($_))
        for @{$dbh->selectcol_arrayref('SHOW DATABASES LIKE ?', undef, $pattern.'\_%')};
}
sub reset_databases {
    drop_extra_databases();
    $dbh->do('DROP DATABASE IF EXISTS '.$dbh->quote_identifier($database));
    $dbh->do('CREATE DATABASE '.$dbh->quote_identifier($database));
    $dbh->do('USE '.$dbh->quote_identifier($database));
}
my $queue = Beanstalk::Client->new($config->{wingman}{beanstalkd});
sub clear_queue {
    # Tests own the test.conf default tube and tubes named after it; other tubes on the dev broker are left alone.
    my $owned = $config->{wingman}{beanstalkd}{default_tube};
    for my $tube (grep { $_ eq $owned || index($_, "$owned.") == 0 } $queue->list_tubes) {
        $queue->use($tube);
        for my $peek (qw(peek_ready peek_delayed peek_buried)) {
            while (my $job = $queue->$peek) { $queue->delete($job->id) }
        }
    }
    $queue->use($owned);
}

my $scratch = tempdir('wing-check-XXXXXX', TMPDIR => 1, CLEANUP => 1);
$config->{log4perl_config} = "$root/author.t/etc/log4perl.conf";
$config->{mkits} = "$root/author.t/var/mkits";
$config->{cache}{root_dir} = "$scratch/cache";
$config->{tenants}{app_dir} = "$root/author.t/tenant_files";
$config->{wingman}{pid_file_path} = "$scratch/wingman.pid";
my $settings = encode_json($config);
sub write_config {
    open my $file, '>', "$scratch/config.json" or die "Cannot write $scratch/config.json: $!\n";
    print $file $settings;
    close $file;
}

delete @ENV{grep { /^WING_/ } keys %ENV};
delete @ENV{qw(PERL5OPT PERL5DB)};
@ENV{qw(WING_HOME WING_APP WING_OWNER WING_CONFIG)} = ($root, "$root/author.t", "$root/author.t", "$scratch/config.json");
my @includes = map { "-I$root/$_" } qw(lib author.t/lib author.t author.t/tenant_files/lib);

my $child;
# Stop the whole running test, including servers it started, before END clears its data.
$SIG{$_} = sub { if ($child) { kill 'TERM', -$child; waitpid $child, 0 } exit 1 } for qw(INT TERM HUP QUIT);
sub run_test {
    defined($child = fork) or die "Cannot start prove: $!\n";
    if (!$child) {
        setpgid(0, 0);
        exec('prove', @includes, @_) or print STDERR "Cannot run prove: $!\n";
        _exit(127); # skip END, which would reset the parent's database and queue
    }
    setpgid($child, $child);
    waitpid $child, 0;
    undef $child;
    return $? == 0;
}
END { my $status = $?; if ($dbh) { reset_databases(); clear_queue() } $? = $status }
reset_databases();
write_config();
system($^X, @includes, '-MWing', '-MDBIx::Class::DeploymentHandler', '-e',
    'my $db = Wing->db; $db->deploy; my $dh = DBIx::Class::DeploymentHandler->new({schema => $db, '
    .'script_directory => "$ENV{WING_APP}/dbicdh"}); $dh->install_version_storage; '
    .'$dh->add_database_version({version => $db->schema_version});') == 0
    or die "Could not deploy the TestWing schema into $database.\n";
my @tables = grep { $_ ne 'dbix_class_deploymenthandler_versions' } @{$dbh->selectcol_arrayref('SHOW TABLES')};
chdir "$root/author.t" or die $!;
my @failed;
for my $test (@tests) {
    # Each test starts from the freshly deployed schema with no rows, cache, queued jobs or config edits.
    drop_extra_databases();
    $dbh->do('SET FOREIGN_KEY_CHECKS = 0');
    $dbh->do('TRUNCATE TABLE '.$dbh->quote_identifier($_)) for @tables;
    $dbh->do('SET FOREIGN_KEY_CHECKS = 1');
    remove_tree("$scratch/cache");
    clear_queue();
    write_config();
    run_test($test) or push @failed, $test =~ s{^\Q$root/\E}{}r;
}
print STDERR "Failed: @failed\n" if @failed;
exit(@failed ? 1 : 0);

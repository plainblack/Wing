use lib '/data/Wing/author.t/lib', '/data/Wing/lib', '/data/Wing/author.t/tenant_files/lib';
use Wing::Perl;
use Data::GUID;
use Test::More;
use Test::Deep;
use Test::TCP;
use TestHelper;

my $andy = Wing->db->resultset('User')->new({
    username    => 'andy',
    real_name   => 'andy',
    email       => 'andy@shawshank.jail',
    use_as_display_name => 'real_name',
});
$andy->encrypt_and_set_password('Saywatanayo');
$andy->insert;

my $prison = Wing->db->resultset('Site')->new({});
$prison->name('Shawshank Prison');
$prison->hostname('shawshank.localhost');
$prison->shortname('shawshank');
$prison->user($andy);
$prison->insert;  ##also builds the tenant db for us

my $site_db = Wing->tenant_db('shawshank');

my $guid = Data::GUID->guid_string;
Wing->config->set('tenant/sso_key', $guid);

##The owner application, where the site will dial back for tenant SSO information.
##This is where the andy user we created above lives.
#my $owner = Test::TCP->new(
#    code => sub {
#        my $port = shift;
#        ##Should inherit the correct ENV from the parent
#        exec 'perl', './tenant_files/bin/account.pl', $port;
#        die "Failed to start account REST server";
#    },
#);

my $owner = Test::TCP->new(
    code => sub {
        my $port = shift;
        use Wing::Perl;
        eval "use Wing::Rest::Session; use Wing::Rest::NotFound;";
        use Plack::Builder;
        use HTTP::Server::Simple::PSGI;
        my $handler = sub {
            use Dancer;

            set port => $port, apphandler   => 'PSGI', startup_info => 0;

            my $env     = shift;
            my $request = Dancer::Request->new(env => $env);
            Dancer->dance($request);
        };

        ##Probably an easier way to do this
        my $app = builder {
            $handler;
        };

        my $server = HTTP::Server::Simple::PSGI->new($port);
        $server->host("127.0.0.1");
        $server->app($app);
        $server->run;
    },
);

Wing->config->set('tenant/sso_hostname', 'http://127.0.0.1:'.$owner->port);

use Wing::Web::Account;
use Wing::Web::NotFound;
use Test::WWW::Mechanize::Dancer;

my $mech = Test::WWW::Mechanize::Dancer->new(
    appdir => '/data/Wing/author.t/tenant_files',
)->mech;

$mech->get_ok('/login');

done_testing();

END {
    Wing->config->delete('tenant/sso_key');
    Wing->config->delete('tenant/sso_hostname');
    Wing->config->delete('tenant');
    $prison->delete;
    TestHelper::cleanup;
}

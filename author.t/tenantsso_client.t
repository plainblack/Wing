use lib '/data/Wing/author.t/lib', '/data/Wing/lib', '/data/Wing/author.t/tenant_files';
use Wing::Perl;
use Data::GUID;
use Test::More;
use Test::Deep;
use Test::Wing::Client;
use Test::TCP;
use Plack::Builder;
use HTTP::Server::Simple::PSGI;
use TestHelper;

my $andy = Wing->db->resultset('User')->new({
    username    => 'andy',
    real_name   => 'andy',
    email       => 'andy@shawshank.jail',
    use_as_display_name => 'real_name',
});
$andy->encrypt_and_set_password('Saywatanayo');
$andy->insert;

my $wing = Test::Wing::Client->new();

my $result;

##Failure testing

my $guid = Data::GUID->guid_string;
Wing->config->set('tenant/sso_key', $guid);

##The owner application, where the site will dial back for tenant SSO information.
##This is where the andy user we created above lives.
my $owner = Test::TCP->new(
    code => sub {
        my $port = shift;
        my $handler = sub {
            use Dancer;

            set port => $port, apphandler   => 'PSGI', startup_info => 0;

            ##Yup, that's it.  The whole server side app
            use Wing::Rest::Session;
            use Wing::Rest::NotFound;

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
Wing->config->set('tenant/sso_hostname', 'http://127.0.0.1:'.$owner->port);

ok(1);

done_testing();

END {
    Wing->config->delete('tenant/sso_key');
    Wing->config->delete('tenant/sso_hostname');
    Wing->config->delete('tenant');
    TestHelper::cleanup();
}

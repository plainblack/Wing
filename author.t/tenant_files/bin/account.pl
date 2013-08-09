use lib qw{ /data/Wing/author.t/lib /data/Wing/lib };
my $port = shift;
use Wing::Perl;
use Wing::Rest::Session;
use Wing::Rest::Status;
use Wing::Rest::NotFound;
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

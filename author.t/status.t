use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Wing;
use Wing::Rest::Status;
use Wing::Rest::NotFound;
use Plack::Test;
use Dancer::Handler;
use HTTP::Request::Common qw(GET);
use JSON qw(decode_json);

set show_errors => 0;
set logger => 'null';
test_psgi(Dancer::Handler->get_handler->psgi_app, sub {
    my $request = shift;
    my $first = $request->(GET 'http://localhost/api/_test');
    my $status = decode_json($first->content)->{result};
    ok exists $status->{tracer}, 'got a tracer back in the description';
    my ($cookie) = $first->header('Set-Cookie') =~ /^(tracer=[^;]+)/;
    my $status2 = decode_json($request->(GET 'http://localhost/api/_test', Cookie => $cookie)->content)->{result};
    is $status2->{tracer}, $status->{tracer}, 'tracer persists across calls';
});
done_testing();

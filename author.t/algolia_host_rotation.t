use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use HTTP::Response;

BEGIN {
    package TestAlgoliaConfig;

    sub get {
        return {
            application_id => 'test-application',
            admin_key      => 'test-admin-key',
            public_key     => 'test-public-key',
        };
    }

    package TestAlgoliaLog;

    sub debug { }
    sub error { }
    sub info  { }

    package Wing;

    my $config = bless {}, 'TestAlgoliaConfig';
    my $log    = bless {}, 'TestAlgoliaLog';

    sub config { return $config; }
    sub log    { return $log; }

    $INC{'Wing.pm'} = __FILE__;
}

use Wing::Algolia;

my @requested_hosts;
my $request_count = 0;

{
    no warnings qw(redefine once);
    local *LWP::UserAgent::new = sub { return bless {}, 'TestAlgoliaUserAgent'; };
    local *TestAlgoliaUserAgent::request = sub {
        my ($self, $request) = @_;
        push @requested_hosts, $request->uri->host;
        $request_count++;
        return HTTP::Response->new($request_count == 1 ? 500 : 200);
    };

    my $algolia = Wing::Algolia->new;
    ok $algolia->delete_index_object('products', 'object-id'),
        'write succeeds when the fallback host responds';
}

is_deeply \@requested_hosts, [
    'test-application.algolia.net',
    'test-application-1.algolianet.com',
], 'a failed primary write is retried against the next configured host';

done_testing();

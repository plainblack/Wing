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

my $request_count = 0;
my $completed;

{
    no warnings qw(redefine once);
    local *LWP::UserAgent::new = sub { return bless {}, 'TestAlgoliaUserAgent'; };
    local *TestAlgoliaUserAgent::request = sub {
        $request_count++;
        return HTTP::Response->new(500);
    };

    my $algolia = Wing::Algolia->new;
    $completed = eval {
        $algolia->delete_index_object('products', 'object-id');
        1;
    };
}

ok !$completed, 'write fails after all configured hosts fail';
like $@, qr/Error updating search index/, 'write reports the Algolia failure';
is $request_count, 4, 'four configured hosts limit the operation to four HTTP attempts';

done_testing();

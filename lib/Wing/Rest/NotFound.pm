package Wing::Rest::NotFound;

use Wing::Dancer;
use Wing::Perl;
use Ouch;
use Dancer;
use Wing::Rest;

any qr{.*} => sub {
    ouch 404, 'Resource Not Found', { path => request->path };
};


1;

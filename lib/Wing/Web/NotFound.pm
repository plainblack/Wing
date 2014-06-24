package Wing::Web::NotFound;

use Wing::Dancer;
use Wing::Perl;
use Ouch;
use Dancer;
use Wing::Web;

any qr{.*} => sub {
    ouch 404, 'Page Not Found', { path => request->path };
};

1;

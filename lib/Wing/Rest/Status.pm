package Wing::Rest::User;

use Wing::Perl;
use Dancer;
use Ouch;
use Wing::Rest;


get '/api/status' => sub {
    return {
        datetime    => Wing->to_RFC3339,
    }
};


1;

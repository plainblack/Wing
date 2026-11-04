package Wing::Web::Admin::Trends;

use Dancer ':syntax';
use Wing::Perl;
use Ouch;
use Wing;
use Wing::Web;
use DateTime;
use Wing::TrendsLogger;

get '/admin/trends/reports' => sub {
    my $user = get_admin_by_session_id();
    template 'admin/trends_reports', {
        current_user => $user
    };
};

get '/admin/trends/reports/manage' => sub {
    my $user = get_admin_by_session_id();
    template 'admin/manage_trends_reports', {
        current_user => $user
    };
};

true;

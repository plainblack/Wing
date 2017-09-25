package Wing::Web::ReportCollector;

use Wing::Perl;
use Ouch;
use Dancer;
use Wing::Web;

any '/_report-collector' => sub {
    use Data::Dumper;
    warn Dumper request->body;
    Wingman->new->put('EmailAllAdmins', { template => 'generic', params => {
        subject => 'WING Security Report Collector',
        message => 'Either we have misconfigured something, or someone is up to no good: '.request->body,
    }});
};

1;

package Wing::Dancer;

use strict;
use warnings;
use Dancer ':syntax';
use Dancer::Plugin;

register site_db => sub {
    my ($db) = @_;
    if ($db) {
        var wing_site_db => $db;
    }
    return vars->{wing_site_db};
};

register site => sub {
    my ($site) = @_;
    if ($site) {
        var wing_site => $site;
    }
    return vars->{wing_site};
};

register_plugin;

1;

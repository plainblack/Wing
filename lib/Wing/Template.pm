package Wing::Template;

use strict;
use warnings;
use Ouch;
use Dancer ':syntax';
use Dancer::Plugin;

$Template::Stash::PRIVATE = 0; # allows options and whatnot access to templates

use Wing::Web;

hook 'before_template_render' => sub {
    my $tokens = shift;
    $tokens->{money} = sub {
                                my $value  = shift || 0;
                                my $digits = shift || 2;
                                return sprintf '$%.'.$digits.'f', $value;
                           };
    $tokens->{int}          = sub { my $value = shift; return $value ? int $value : 0; };
    $tokens->{text_as_html} = sub {
        my $text = shift;
        $text =~ s/\&/&amp;/g;
        $text =~ s/\</&lt;/g;
        $text =~ s/\>/&gt;/g;
        $text =~ s/\n/<br>/g;
        return $text;
    };
    $tokens->{system_alert_message} = Wing->cache->get('system_alert_message');
    if (exists $tokens->{current_user} && $tokens->{current_user}) {
        my $current_user = delete $tokens->{current_user};
        $tokens->{current_user} = describe($current_user, current_user => $current_user, include_relationships => 1, include_options => 1, include_private => 1, );
    }
};

register_plugin;

1;

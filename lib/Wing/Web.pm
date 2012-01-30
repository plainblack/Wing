package Wing::Web;

use strict;
use warnings;
use Ouch;
use Dancer ':syntax';
use Wing::Dancer;
use Wing::Session;
use Dancer::Plugin;
use DateTime::Format::Strptime;
use DateTime::Format::RFC3339;

$Template::Stash::PRIVATE = 0; # allows options and whatnot access to templates

register get_session => sub {
    my ($session_id) = @_;
    $session_id ||= params->{session_id};
    my $cookie = cookies->{session_id};
    if (!defined $session_id && defined $cookie) {
        $session_id = $cookie->value;
    }
    return undef unless $session_id;
    return $session_id if (ref $session_id eq 'Wing::Session');
    my $session = Wing::Session->new(id => $session_id, db => site_db());
    if ($session->user_id) {
        $session->extend;
        return $session;
    }
    else {
        return undef;
    }
};

register get_user_by_session_id => sub {
    my $session = get_session(@_);
    if (defined $session) {
        return $session if (ref $session =~ m/DB::Result::User$/);
        my $user = $session->user;
        if (defined $user) {
            header 'CacheControl', 'no-cache';
            header 'Pragma', 'no-cache';
            header 'Expires', '-1';
            return $user;
        }
    }
    ouch 401, 'You must log in to do that.'
};


register get_admin_by_session_id => sub {
    my $user = get_user_by_session_id(@_);
    if (defined $user) {
        if ($user->is_admin) {
            return $user;
        }
        else {
            ouch 450, 'You must be an admin to do that.';
        }
    }
    else {
        ouch 401, 'You must log in to do that.';
    }
};

register describe => sub {
    my ($object, $current_user) = @_;
    $current_user ||= eval { get_user_by_session_id() };
    return $object->describe(
        include_private         => 1,
        include_admin           => 1,
        include_options         => 1,
        include_related_objects => 1,
        current_user            => $current_user,
        tracer                  => get_tracer(),
    );
};

register template_vars => sub {
    my ($current_user, %vars) = @_;
    my %params;
    if (defined $current_user) {
        $vars{current_user} = describe($current_user, $current_user);
        if ($current_user->is_admin) {
           $params{is_admin} = 1;
        }
    }
    $vars{money}        = sub { sprintf '$%.2f', shift || 0 };
    $vars{int}          = sub { my $value = shift; return $value ? int $value : 0; };
    $vars{text_as_html} = sub {
        my $text = shift;
        $text =~ s/\&/&amp;/g;
        $text =~ s/\</&lt;/g;
        $text =~ s/\>/&gt;/g;
        $text =~ s/\n/<br>/g;
        return $text;
    };
    $vars{date}         = sub {
        my ($date_string, $format) = @_;
        return DateTime::Format::Strptime->new(pattern => $format)->format_datetime(DateTime::Format::RFC3339->new->parse_datetime($date_string));
    };
    $vars{system_alert_message} = Wing->cache->get('system_alert_message');
    return \%vars;
};

hook before_error_init => sub {
    my $error = shift;
    if (ref $error->exception eq 'Ouch') {
        my $exception = $error->exception;
        my $code = ($exception->code > 399 && $exception->code < 1000) ? $exception->code : 500; # gotta make sure it's an HTTP code
        $error->{code} = $code;
        $error->{title} = $exception->message;
        $error->{message} = $exception->scalar;
    }
    else {
        $error->{code} = 500;
        $error->{title} = 'Somthing bad happened: '.$error->message;
    }
};

register_plugin;

1;

package Wing::Web;

use strict;
use warnings;
use Ouch;
use Dancer ':syntax';
use Wing::Session;
use Dancer::Plugin;
use DateTime::Format::Strptime;

$Template::Stash::PRIVATE = 0; # allows options and whatnot access to templates

require Wing::Dancer;

register get_session => sub {
    my (%options) = @_;
    my $session_id = $options{session_id} || params->{session_id};
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

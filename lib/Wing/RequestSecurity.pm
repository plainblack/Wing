package Wing::RequestSecurity;

use strict;
use warnings;

sub session_cookie_options {
    my ($request, $path) = @_;
    return (expires => '+5y', http_only => 0, path => $path,
        same_site => 'Lax', secure => $request->secure);
}

1;

=head1 NAME

Wing::RequestSecurity - Session cookie options

=head1 API

C<session_cookie_options($dancer_request, $path)> returns the options for a
session cookie: a five-year expiry, the given path, readable by JavaScript,
C<SameSite=Lax>, and C<Secure> when C<< $request->secure >> is true.

Dancer 1.3522 resolves the scheme using forwarded headers only with
C<behind_proxy>. Enable that setting only behind an ingress that overwrites
forwarded protocol and host headers and blocks direct access to the app.

=cut

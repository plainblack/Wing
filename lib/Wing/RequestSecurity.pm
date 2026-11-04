package Wing::RequestSecurity;

use strict;
use warnings;
use URI;
use Socket qw(AF_INET6 inet_pton);

sub canonical_origin {
    my ($value) = @_;
    return unless defined $value && $value =~ m{\A(https?)://(\[[0-9a-fA-F:.]+\]|[a-zA-Z0-9.-]+)(?::([0-9]+))?\z}i;
    my ($host, $port) = (lc $2, $3);
    if ($host =~ /^\[(.*)\]$/) {
        return unless inet_pton(AF_INET6, $1);
    }
    else {
        return if length($host) > 253;
        return unless $host =~ /\A[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\.?\z/;
        for my $label (split /\./, $host) {
            return unless $label =~ /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/;
        }
    }
    return if defined $port && ($port < 1 || $port > 65535);
    return URI->new($value)->canonical->as_string;
}

sub same_origin_error {
    my ($request) = @_;
    my @sites = $request->header('Sec-Fetch-Site');
    my @origins = $request->header('Origin');
    my $message = 'This request requires the same origin. Reload the form on this site and submit it again.';
    return $message if grep { /(?:\A|[\s,])cross-site(?:\z|[\s,])/i } @sites;
    return unless @origins;
    return $message unless @origins == 1;
    my $origin = canonical_origin($origins[0]);
    my $target = canonical_origin($request->scheme . '://' . $request->host);
    return $message unless defined $origin && defined $target && $origin eq $target;
    return;
}

sub session_cookie_options {
    my ($request, $path) = @_;
    return (expires => '+5y', http_only => 0, path => $path,
        same_site => 'Lax', secure => $request->secure);
}

1;

=head1 NAME

Wing::RequestSecurity - Browser request origin validation

=head1 API

C<same_origin_error($dancer_request)> returns a human-readable refusal or undef.
It performs no session, cache or database lookup and does not send a response.
Call it before authentication or mutations, outside any eval that could swallow
refusals. Headerless clients are allowed. Origin must be one HTTP(S) origin,
matching scheme, host and effective port; cross-site fetch metadata is refused.

Dancer 1.3522 resolves scheme and host using forwarded headers only with
C<behind_proxy>. Enable that setting only behind an ingress that overwrites
forwarded protocol and host headers and blocks direct access to the app.

=cut

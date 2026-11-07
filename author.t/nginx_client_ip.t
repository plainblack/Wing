use strict;
use warnings;
use FindBin;
use Test::More;

# nginx fills these variables itself, so a client cannot choose the address, scheme or host the apps see.
open my $file, '<', "$FindBin::Bin/../var/init/etc/nginx.conf" or die "Cannot read the generated nginx template: $!";
my $template = do { local $/; <$file> };
my %headers = $template =~ /^\s*proxy_set_header\s+(\S+)\s+([^;]+);/mg;
is $headers{'X-Real-IP'}, '$remote_addr', 'X-Real-IP is the single client address nginx resolved';
is $headers{'X-Forwarded-Proto'}, '$scheme', 'X-Forwarded-Proto is the scheme nginx received';
is $headers{'X-Forwarded-Host'}, '$http_host', 'X-Forwarded-Host is the host the request reached';
is $headers{Host}, '$host', 'Host is the request host';
like $template, qr/^\s*real_ip_header\s+X-Forwarded-For;/m, 'trusted proxies name the client in X-Forwarded-For';
like $template, qr/^\s*real_ip_recursive\s+on;/m, 'the client is the last address no trusted proxy added';
unlike $template, qr/^\s*set_real_ip_from/m, 'no proxy is trusted until the installation lists its load balancers';
done_testing;

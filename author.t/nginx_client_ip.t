use strict;
use warnings;
use FindBin;
use Test::More;

# nginx fills these variables itself, so a client cannot choose the address, scheme or host the apps see.
open my $file, '<', "$FindBin::Bin/../var/init/etc/nginx.conf" or die "Cannot read the generated nginx template: $!";
my %headers = do { local $/; <$file> } =~ /proxy_set_header\s+(\S+)\s+([^;]+);/g;
is $headers{'X-Real-IP'}, '$proxy_add_x_forwarded_for', 'X-Real-IP appends the observed peer after any supplied addresses';
is $headers{'X-Forwarded-Proto'}, '$scheme', 'X-Forwarded-Proto is the scheme nginx received';
is $headers{'X-Forwarded-Host'}, '$http_host', 'X-Forwarded-Host is the host the request reached';
is $headers{Host}, '$host', 'Host is the request host';
done_testing;

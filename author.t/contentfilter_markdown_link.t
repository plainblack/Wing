use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
BEGIN {
    unshift @INC, "$ENV{WING_APP}/lib" if $ENV{WING_APP};
}
use Test::More;

use Wing::ContentFilter;

my $markdown_link = '[https://protospiel.online/designchallenge](https://protospiel.online/designchallenge)';
Wing::ContentFilter::format_markdown(\$markdown_link);

{
    no warnings 'redefine';
    local *Wing::ContentFilter::format_link = sub {
        my $uri = shift;
        return '<enriched>'.$uri->as_string.'</enriched>';
    };
    Wing::ContentFilter::find_and_format_uris(\$markdown_link, { links => 1 });
}

is $markdown_link,
    '<p><a href="https://protospiel.online/designchallenge">https://protospiel.online/designchallenge</a></p>',
    'does not enrich a URL already inside a Markdown link';

my $mixed_links = '<p><a href="https://example.com/kept">Kept link</a> and https://example.com/enriched</p>';
my $found;
{
    no warnings 'redefine';
    local *Wing::ContentFilter::format_link = sub {
        my $uri = shift;
        return '<enriched>'.$uri->as_string.'</enriched>';
    };
    $found = Wing::ContentFilter::find_and_format_uris(\$mixed_links, { links => 1 });
}

is $mixed_links,
    '<p><a href="https://example.com/kept">Kept link</a> and <enriched>https://example.com/enriched</enriched></p>',
    'still enriches a bare URL outside an existing link';
is $found, 1, 'reports only the bare URL as found';

done_testing;

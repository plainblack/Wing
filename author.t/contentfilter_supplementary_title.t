use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib", "$FindBin::Bin/../lib";
use Test::More;
use URI;

use Wing::ContentFilter;

{
    package Local::LinkTitleResponse;

    sub is_success { return 1 }
    sub header { return 'text/html; charset=utf-8' }
    sub decoded_content { return '<html><title>unused</title></html>' }
}

{
    package Local::LinkTitleAgent;

    sub timeout { return }
    sub ssl_opts { return }
    sub get { return bless {}, 'Local::LinkTitleResponse' }
}

{
    package Local::OpenGraph;

    sub property {
        my ($self, $name) = @_;
        return $name eq 'title' ? "Balloon \x{1F388} title" : undef;
    }
}

{
    package Local::LinkTitleConfig;

    sub get { return 'thegamecrafter.com' }
}

my $html;
{
    no warnings qw(redefine once);
    local *LWP::UserAgent::new = sub { return bless {}, 'Local::LinkTitleAgent' };
    local *Data::OpenGraph::parse_string = sub { return bless {}, 'Local::OpenGraph' };
    local *Wing::config = sub { return bless {}, 'Local::LinkTitleConfig' };

    $html = Wing::ContentFilter::format_link(URI->new('https://example.com/game'));
}

like($html, qr/Balloon &#x1F388; title/, 'preserves a supplementary character as an HTML entity');
unlike($html, qr/[\x{10000}-\x{10FFFF}]/, 'does not return four-byte characters that truncate a MySQL utf8 field');
like($html, qr{</a>}, 'returns a complete anchor after encoding the remote title');

done_testing;

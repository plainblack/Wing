package Wing::ContentFilter;

use Wing;
use Wing::Perl;
use pQuery;
use Data::OpenGraph;
use LWP::UserAgent;
use Text::MultiMarkdown;
use URI::Find::Delimited;

sub neutralize_html {
    my ($content, $allowed) = @_;
    ${$content} =~ s/\&/&amp;/g unless $allowed->{entities};            # replace & with &amp; unless we're ok with entities
    ${$content} =~ s/\</&lt;/g;                                         # disable HTML tags
    ${$content} =~ s/\>/&gt;/g;
}

sub format_markdown {
    my ($content) = @_;
    my $m = Text::MultiMarkdown->new(
        empty_element_suffix => '>',
        tab_width => 2,
        disable_definition_lists => 1,
        disable_bibliography => 1,
        disable_footnotes => 1,
        strip_metadata => 1,
    );
    ${$content} = $m->markdown(${$content});
    ${$content} =~ s{<table>}{<table class="table table-striped">}xmsg;
}

sub format_html {
    my ($content, $allowed) = @_;
    neutralize_html($content);
    unless ($allowed->{with_markdown}) {
        ${$content} =~ s/\*{2}(.*?)\*{2}/<strong>$1<\/strong>/g;            # bold stuff marked with **
    }
    ${$content} =~ s/\_{2}(.*?)\_{2}/<em>$1<\/em>/g;                    # italicize stuff marked with __
    ${$content} =~ s/\~{2}(.*?)\~{2}/<s>$1<\/s>/g;                      # strike through stuff makred with ~~
    ${$content} =~ s/^\s*\&gt;\s*(.*)$/<blockquote>$1<\/blockquote>/gm; # block quote with >
    ${$content} =~ s/\{(.*?)\}/<a name="$1"><\/a>/g;                      # in page target
    unless ($allowed->{with_markdown}) {
        ${$content} =~ s/^\s*(\-{3,})\s*$/<hr>/gm;                          # --- creates a horizontal rule
        my @headings = (6,5,4,3,2);                                                 # each = at the start of a line creates H1 through H6 tags
        if (exists $allowed->{headings}) {
           if (ref $allowed->{headings} eq 'ARRAY') {
               @headings = reverse sort @{$allowed->{headings}};
           }
           else {
               warn "Allowed headings should be an array ref of numbers 1 through 6.";
           }
       }
       foreach my $i (@headings) {
           ${$content} =~ s/^\s*\#{\Q$i\E}\s*(.*)$/<h$i>$1<\/h$i>/gm;
       }
       ${$content} =~ s{((?:(\n\s*[+-]))(?s:.+?)(?:\z|\n(?!(\s*[+-]))))}{  # convert lines starting with - or + into bulleted lists
               my $list = "<ul>".$1."</ul>";
               $list =~ s/^\s*[+-]\s*(.*?)$/<li>$1<\/li>/gmr;
       }ge;
       ${$content} =~ s/\n/<br>/g;                                         # convert carriage returns into break tags
       ${$content} =~ s/(<\/(h1|h2|h3|h4|h5|h6|ul|ol|li)>)(<br>)+/$1/g;    # some tags should not be surrounded by break tags
       ${$content} =~ s/(<br>)+(<(h1|h2|h3|h4|h5|h6|ul|ol|li)>)/$2/g;
   }
}

sub format_line_item {
    my ($content) = @_;
    ${$content} =~ s/^\s*[+-]\s*(.*?)$/<li>$1<\/li>/gm;
}

sub find_and_format_uris {
    my ($content, $allowed) = @_;
    my $finder = URI::Find::Delimited->new(
        delimiter_re  => [ '\(', '\)' ], # ignore markdown urls
        callback => sub {
            my ($opening_delim, $closing_delim, $uri_string, $title, $whitespace) = @_;

            if ($opening_delim) { # we found a markdown url
                return $opening_delim.$uri_string.$closing_delim;
            }

            my $uri = URI->new($uri_string);

            # normal youtube
            if ($allowed->{youtube} && $uri->host eq 'www.youtube.com') {
                if ($uri->path eq '/watch') {
                    my %params = $uri->query_form;
                    return format_youtube($params{v});
                }
                elsif ($uri->path =~ m{/v/([\w\-_]+)}xms) {
                    return format_youtube($1);
                }
                elsif ($allowed->{links}) {
                    return format_link($uri);
                }
                else {
                    return $uri->as_string;
                }
            }

            # short youtube
            elsif ($allowed->{youtube} && $uri->host eq 'youtu.be') {
                return format_youtube(substr($uri->path, 1));
            }

            # vimeo
            elsif ($allowed->{vimeo} && $uri->host eq 'vimeo.com') {
                return format_vimeo(substr($uri->path, 1));
            }

            # images
            elsif ($allowed->{images} && $uri->path =~ m/(\.jpg|\.jpeg|\.gif|\.png)$/i) {
                return format_image($uri);
            }

            # links
            elsif ($allowed->{links}) {
                return format_link($uri);
            }

            # just put the uri back into the text
            else {
                return $uri->as_string;
            }
        },
    );
    $finder->find($content);
}

sub format_link {
    my $uri = shift;
    my $ua = LWP::UserAgent->new;
    $ua->timeout(5);
    $ua->ssl_opts( verify_hostname => 0 ,SSL_verify_mode => 0x00);
    # have to send a BS user agent so stupid web sites like gamesalute.com don't block us
    my $response = $ua->get($uri->as_string, Accept => 'text/html;q=0.9,*/*;q=0.8', 'Accept-Encoding' => 'gzip, deflate', 'Accept-Language' => 'en-us', 'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_5) AppleWebKit/536.28.10 (KHTML, like Gecko) Version/6.0.3 Safari/536.28.10', 'Cache-Control' => 'max-age=0');
    if ($response->is_success && $response->header('Content-Type') =~ m{^text/html}xms) {
        my $og = Data::OpenGraph->parse_string($response->decoded_content);
        my $title = $og->property('title');
        unless ($title) {
            $title = pQuery($response->decoded_content)->find('title')->html();
        }
        format_html(\$title);
        if ($uri->host eq Wing->config->get('sitename')) {
            return sprintf '<a href="%s">%s</a>', $uri->as_string, $title || $uri->as_string;
        }
        else {
            return sprintf '<a href="%s" target="_new" title="Links to external site: %s">%s <small><span class="glyphicon glyphicon-new-window"></span></a></small>', $uri->as_string, $uri->host, $title || $uri->as_string;
        }
    }
    else {
        warn $response->status_line;
        return $uri;
    }
}

sub format_image {
    my $uri = shift;
    my @segments = $uri->path_segments;
    my $alt = $segments[-1];
    my $url = $uri->as_string;
    return '<img src="'.$url.'" alt="'.$alt.'" class="img-responsive">';
}

sub format_youtube {
    my $id = shift;
    return q{<div class="embed-responsive embed-responsive-4by3"><iframe class="youtube_video embed-responsive-item" src="https://www.youtube.com/embed/}.$id.q{?rel=0" frameborder="0" allowfullscreen></iframe></div>};
}

sub format_vimeo {
    my $id = shift;
    return q{<div class="embed-responsive embed-responsive-4by3"><iframe class="vimeo_video embed-responsive-item" src="https://player.vimeo.com/video/}.$id.q{" frameborder="0"></iframe></div>};
}

1;

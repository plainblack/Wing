use strict;
use lib '/data/Wing/author.t/lib', '/data/Wing/lib';
use Test::More;
use URI;
use Wing::Perl;

use_ok 'Wing::ContentFilter';

my $image_uri = URI->new('https://cf.geekdo-static.com/images/geekdo/bgg_cornerlogo.png');
is Wing::ContentFilter::format_image($image_uri), '<img src="https://cf.geekdo-static.com/images/geekdo/bgg_cornerlogo.png" alt="bgg_cornerlogo.png" class="img-responsive">', 'format_image';

my $find_link_in_text = 'foo https://www.thegamecrafter.com/help bar';
Wing::ContentFilter::find_and_format_uris(\$find_link_in_text, {links => 1});
is $find_link_in_text, 'foo <a href="https://www.thegamecrafter.com/help">Help</a> [www.thegamecrafter.com] bar', 'can find links embedded in text';

my $just_a_url = 'https://www.youtube.com/watch?v=YKmj6LI5pfs';
Wing::ContentFilter::find_and_format_uris(\$just_a_url, {youtube => 1});
is $just_a_url, '<div class="embed-responsive embed-responsive-4by3"><iframe class="youtube_video embed-responsive-item" src="https://www.youtube.com/embed/YKmj6LI5pfs?rel=0" frameborder="0" allowfullscreen></iframe></div>', 'just a url';

my $text = 'This is <b>bold</b> &
This is <i>italic</i>.';
Wing::ContentFilter::format_html(\$text);
is $text, 'This is &lt;b&gt;bold&lt;/b&gt; &amp;<br>This is &lt;i&gt;italic&lt;/i&gt;.', 'can strip html';

my $hr = 'foo
---
 ---
 foo --- bar
---------
bar';
Wing::ContentFilter::format_html(\$hr);
is $hr, 'foo<br><hr><br><hr><br> foo --- bar<br><hr><br>bar', 'can format horizontal rule';

my $bold = '**bold** or ** bold **
or **bold**, foo, but not **bo
ld**.';
Wing::ContentFilter::format_html(\$bold);
is $bold, '<strong>bold</strong> or <strong> bold </strong><br>or <strong>bold</strong>, foo, but not **bo<br>ld**.', 'can format bold';

my $italic = '__italic__ or __ italic __
or __italic__, foo, but not __ital
ic__.';
Wing::ContentFilter::format_html(\$italic);
is $italic, '<em>italic</em> or <em> italic </em><br>or <em>italic</em>, foo, but not __ital<br>ic__.', 'can format italic';

my $strike = '~~strike~~ or ~~ strike ~~
or ~~strike~~, foo, but not ~~str
ike~~.';
Wing::ContentFilter::format_html(\$strike);
is $strike, '<s>strike</s> or <s> strike </s><br>or <s>strike</s>, foo, but not ~~str<br>ike~~.', 'can format strike';

my $heading = 'foo
= heading 1
==heading2
 ===heading 3 is good
==== head 4
foo = head none
too
=====head5
====== head6
bar';
my $heading2 = $heading;
Wing::ContentFilter::format_html(\$heading, {headings => [1,2,3,4,5,6]});
is $heading, 'foo<h1>heading 1</h1><h2>heading2</h2><h3>heading 3 is good</h3><h4>head 4</h4>foo = head none<br>too<h5>head5</h5><h6>head6</h6>bar', 'can format headings';
Wing::ContentFilter::format_html(\$heading2);
is $heading2, 'foo<br>= heading 1<h2>heading2</h2><h2>=heading 3 is good</h2><h2>== head 4</h2>foo = head none<br>too<h2>===head5</h2><h2>==== head6</h2>bar', 'by default only allow level 2 headings';

my $list = 'foo
bar
 - this is
+ a
- list of epic proportions
-and more
foo
bar';
my $list2 = $list.$list;
Wing::ContentFilter::format_html(\$list);
is $list, 'foo<br>bar<ul><li>this is</li><li>a</li><li>list of epic proportions</li><li>and more</li></ul>foo<br>bar','can format a list';

Wing::ContentFilter::format_html(\$list2);
is $list2, 'foo<br>bar<ul><li>this is</li><li>a</li><li>list of epic proportions</li><li>and more</li></ul>foo<br>barfoo<br>bar<ul><li>this is</li><li>a</li><li>list of epic proportions</li><li>and more</li></ul>foo<br>bar','can format multiple lists';



done_testing();

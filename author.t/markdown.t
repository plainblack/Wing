use strict;
use lib '/data/Wing/author.t/lib', '/data/Wing/lib';
use Test::More;
use URI;
use Wing::Perl;

use_ok 'Wing::Markdown';

my $m = Wing::Markdown->new;

isa_ok $m, 'Wing::Markdown';

is $m->markdown('**bold**'), '<p><strong>bold</strong></p>', 'bold';
is $m->markdown('_italics_'), '<p><em>italics</em></p>', 'italics';
is $m->markdown('`code`'), '<p><code>code</code></p>', 'code';
is $m->markdown('>quote'), "<blockquote>\n  <p>quote</p>\n</blockquote>", 'quote';
is $m->markdown('---'), '<hr>', 'horizontal rule';

is $m->markdown('#heading 1'), "<h1>heading 1</h1>", 'heading 1';
is $m->markdown('##heading 2'), "<h2>heading 2</h2>", 'heading 2';
is $m->markdown('###heading 3'), "<h3>heading 3</h3>", 'heading 3';
is $m->markdown('####heading 4'), "<h4>heading 4</h4>", 'heading 4';
is $m->markdown('#####heading 5'), "<h5>heading 5</h5>", 'heading 5';
is $m->markdown('######heading 6'), "<h6>heading 6</h6>", 'heading 6';

is $m->markdown("+ foo\n+ bar"), "<ul>\n<li>foo</li>\n<li>bar</li>\n</ul>", 'unordered list';
is $m->markdown("1. foo\n2. bar"), "<ol>\n<li>foo</li>\n<li>bar</li>\n</ol>", 'ordered list';

is $m->markdown('[My Custom Title](https://tabletop.events)'), '<p><a href="https://tabletop.events">My Custom Title</a></p>', 'link';
is $m->markdown('[![Alt text](https://tabletop.events/tte1/img/frontpage/coninabox.png)](https://tabletop.events) '), '<p><a href="https://tabletop.events"><img src="https://tabletop.events/tte1/img/frontpage/coninabox.png" alt="Alt text" class="img-responsive"></a> </p>', 'linked image';

is $m->markdown('![Alt text](https://tabletop.events/tte1/img/frontpage/coninabox.png)'), '<p><img src="https://tabletop.events/tte1/img/frontpage/coninabox.png" alt="Alt text" class="img-responsive"></p>', 'image';
is $m->markdown('![Alt text](https://tabletop.events/tte1/img/frontpage/coninabox.png right)'), '<p><img src="https://tabletop.events/tte1/img/frontpage/coninabox.png" alt="Alt text" class="img-responsive pull-right"></p>', 'image pulled right';

my $tabletext =<<EOF;
| Fruit         | Color           | Price  | 
| ----------- |:-------------:| -------:| 
| Apple       | red              | 3       | 
| Orange    | orange        |   12   | 
| Pear        | green          |    1    |
EOF

my $tableresult =<<EOF;
<table class="table table-striped">
<col>
<col align="center">
<col align="right">
<col>
<thead>
<tr>
\t<th>Fruit</th>
\t<th>Color</th>
\t<th>Price</th>
\t<th> </th>
</tr>
</thead>
<tbody>
<tr>
\t<td>Apple</td>
\t<td align="center">red</td>
\t<td align="right">3</td>
\t<td> </td>
</tr>
<tr>
\t<td>Orange</td>
\t<td align="center">orange</td>
\t<td align="right">12</td>
\t<td> </td>
</tr>
<tr>
\t<td>Pear</td>
\t<td align="center">green</td>
\t<td align="right">1</td>
</tr>
</tbody>
EOF
$tableresult .= '</table>';

is $m->markdown($tabletext), $tableresult, 'table';

is $m->markdown("##Foo Bar\n".'**bold**![Test](https://evercondotorg.files.wordpress.com/2016/06/lloydm.jpg?w=50 right) Lloyd Metcalf is a full time RPG artist'), '<h2>Foo Bar</h2>'."\n\n".'<p><strong>bold</strong><img src="https://evercondotorg.files.wordpress.com/2016/06/lloydm.jpg?w=50" alt="Test" class="img-responsive pull-right"> Lloyd Metcalf is a full time RPG artist</p>', 'bring it all together';


done_testing();

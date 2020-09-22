package Wing::Rest::IdeaComment;

use Wing::Perl;
use Wing;
use Dancer;
use Ouch;
use Wing::Rest;

get '/api/ideacomment' => sub {
    ##remove the eval for data accessible only by registered users
    my $user = eval { get_user_by_session_id() };
    my $ideacomments = site_db()->resultset('IdeaComment')->search({
        -or => {
            'me.name' => { like => params->{query}.'%'},
            #'me.description' => { like => params->{query}.'%'}, # pretty damn slow, suggest using a real search engine rather than a database
        }
    }, {
        order_by => { -desc => 'me.date_created' }
    });
    return format_list($ideacomments, current_user => $user);
};

post '/api/ideacomment/:id/like' => sub {
    my $user = get_user_by_session_id();
    my $comment = fetch_object('IdeaComment');
    $comment->like($user->id);
    return describe($comment, current_user => $user);
};

del '/api/ideacomment/:id/like' => sub {
    my $user = get_user_by_session_id();
    my $comment = fetch_object('IdeaComment');
    $comment->unlike($user->id);
    return describe($comment, current_user => $user);
};

generate_create('IdeaComment',  extra_processing => sub {
    my ($comment, $user) = @_;
    if (param('subscribe')) {
        $comment->idea->add_subscription($user->id);
    }
});
generate_read('IdeaComment');
generate_update('IdeaComment');
generate_delete('IdeaComment');
generate_options('IdeaComment');
generate_all_relationships('IdeaComment');

1;

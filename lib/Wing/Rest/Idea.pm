package Wing::Rest::Idea;

use Wing::Perl;
use Dancer;
use Wing::Rest;
use Wing::Dancer;
use Ouch;

sub get_next_unvoted_idea {
    my ($user) = @_;
    my $voted_ideas = Wing->db->resultset('IdeaOpinion')->search({
        user_id => $user->id,
    });
    my $next_idea = Wing->db->resultset('Idea')->search({
        id      => { -not_in => $voted_ideas->get_column('idea_id')->as_query },
        locked  => { '<>' => 1 },
    },{ order_by => \'rand()', rows => 1})->single;
    return $next_idea;
}

get '/api/idea' => sub {
    my $user = eval { get_user_by_session_id(); };
    my $ideas = Wing->db->resultset('Idea')->new({})->search_ideas({ params(), }, $user );
    return format_list($ideas)
};

get '/api/idea/:id/opinions' => sub {
    get_user_by_session_id();
    my $idea = fetch_object('Idea');
    my $opinions = $idea->opinions->search(undef,{order_by => 'date_created'});
    return format_list($opinions);
};

any ['post','put'] => '/api/idea/:id/opinions' => sub {
    my $user = get_user_by_session_id();
    my $idea = fetch_object('Idea');
    if ($idea->locked) {
        ouch 423, "Sorry, this idea is currently locked from changes.";
    }
    my $params = expanded_params();

    my $opinion = $idea->opinions->search({ -or => { user_id => $user->id }},{rows=>1})->single;
    if (defined $opinion) {
        $opinion->verify_posted_params($params, $user);
        $opinion->update;
    }
    else {
        $opinion = Wing->db()->resultset('IdeaOpinion')->new({});
        $opinion->idea($idea);
        $opinion->verify_creation_params($params, $user);
        $opinion->verify_posted_params($params, $user);
        $opinion->insert;
    }

    if ($params->{next}) {
        my $idea = get_next_unvoted_idea($user);
        if ($idea) {
            return describe($idea, current_user => $user);
        }
        else {
            return {};
        }
    }
    else {
        $idea = $idea->get_from_storage;
        return describe($idea, current_user => $user);
    }
};

post '/api/idea/:idea1_id/merge' => sub {
    my $user = get_user_by_session_id()->verify_is_admin;
    my $idea1_id = param('idea1_id');
    my $idea2_id = param('idea2_id') or ouch 424, "No value passed for idea2_id";
    my $idea1 = Wing->db->resultset('Idea')->find($idea1_id) or ouch 424, "Couldn't find idea1 by ID";
    my $idea2 = Wing->db->resultset('Idea')->find($idea2_id) or ouch 424, "Couldn't find idea2 by ID";
    eval {
        $idea1->merge( $idea2 );
    };
    $@ and ouch 424, "Merging ideas failed: " . $@;
    return describe($idea1, current_user => $user);
};


get '/api/idea/low-vote' => sub {
    my $user = get_user_by_session_id();
    my $idea = get_next_unvoted_idea($user);
    return {} unless $idea;
    return describe($idea, current_user => $user);
};

put '/api/idea/:id/lock' => sub {
    my $user = get_user_by_session_id()->verify_is_admin;
    my $status = params->{status} or ouch 424, "You must choose a status when closing an idea";
    my $idea = fetch_object('Idea');
    $idea->lock(params->{status});
    return describe($idea, current_user => $user);
};

put '/api/idea/:id/unlock' => sub {
    my $user = get_user_by_session_id()->verify_is_admin;
    my $idea = fetch_object('Idea');
    $idea->unlock;
    return describe($idea, current_user => $user);
};

post '/api/idea/:id/subscription' => sub {
    my $user = get_user_by_session_id();
    my $idea = fetch_object('Idea');
    my $subscription = $idea->add_subscription($user->id);
    if (defined $subscription) {
        $idea = $idea->get_from_storage;
    }
    return describe($idea, current_user => $user);
};

del '/api/idea/:id/subscription' => sub {
    my $user = get_user_by_session_id();
    my $idea = fetch_object('Idea');
    my $subscription = $idea->remove_subscription($user->id);
    if (defined $subscription) {
        $idea = $idea->get_from_storage;
    }
    return describe($idea, current_user => $user);
};

my $is_admin = sub {
    my ($object, $user) = @_;
    ouch 450, 'Insufficient privileges to delete Idea'
        unless $user->is_admin;
};

generate_options('Idea');
generate_read('Idea');
generate_create('Idea');
generate_update('Idea');
generate_delete('Idea', extra_processing => $is_admin, );
generate_all_relationships('Idea');

1;

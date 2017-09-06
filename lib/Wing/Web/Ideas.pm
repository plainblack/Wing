package Wing::Web::Ideas;

use Dancer ':syntax';
use Wing::Perl;
use Ouch;
use Wing;
use Wing::Web;

get '/ideas' => sub {
    my $user = eval { get_user_by_session_id(); };
    template 'ideas/index', {
        current_user => $user,
    };
};

get '/idea/:id/:uri_part?' => sub {
    forward '/idea/'.params->{id};
};

get '/idea/:id' => sub {
    my $user = eval { get_user_by_session_id(); };
    my $idea = fetch_object('Idea');
    my $details = describe($idea, include_relationships => 1, current_user => $user);
    template 'ideas/view', {
        current_user => $user,
        idea      => $details,
    };
};

true;

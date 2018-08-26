package Wing::Web::Chat;

use Dancer ':syntax';
use Wing::Perl;
use Ouch;
use Wing;
use Wing::Web;

get '/chat' => sub {
    my $user = get_user_by_session_id();
    my $firebase_config = Wing->config->get('firebase');
    template 'chat', {
        firebase    => {
            jwt         => $user->firebase_jwt({ moderator => $user->is_chat_moderator, staff => $user->is_chat_staff }),
            id          => $firebase_config->{id},
            database    => $firebase_config->{database},
            api_key     => $firebase_config->{api_key},
        },
        user        => {
            id          => $user->id,
            name        => $user->display_name,
            avatar_uri  => $user->determine_avatar_uri,
            profile_uri => '//'.Wing->config->get('sitename').$user->view_uri,
            moderator   => $user->is_chat_moderator,
            staff       => $user->is_chat_staff,
        },
    };
};

true;

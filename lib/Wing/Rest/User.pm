package Wing::Rest::User;

use Wing::Perl;
use Dancer;
use Ouch;
use Wing::Rest;

# SSO sessions without view_my_account see only public fields, as generated reads do.
sub session_user_and_viewer {
    my $user = get_user_by_session_id();
    my $session = $user->current_session;
    return ($user, $user) if eval { $session->check_permissions(['view_my_account']) };
    die $@ unless kiss(450);
    return ($user, undef);
}

# Only admins may see other users' email (can_view), so only they may search it.
sub user_search {
    my $viewer = shift;
    my $like = { like => (params->{query} || '').'%' };
    return { -or => { username => $like, real_name => $like, (defined $viewer && $viewer->is_site_admin ? (email => $like) : ()) } };
}

get '/api/user' => sub {
    my (undef, $viewer) = session_user_and_viewer();
    my $users = site_db()->resultset('User')->search(user_search($viewer), {order_by => 'username'});
    return format_list($users, current_user => $viewer);
};

get '/api/user/whoami' => sub {
    my ($user, $viewer) = session_user_and_viewer();
    return describe($user, current_user => $viewer);
};

get '/api/user-not-me' => sub {
    my ($user, $viewer) = session_user_and_viewer();
    my $users = site_db()->resultset('User')->search({ %{user_search($viewer)}, id => { '<>' => $user->id } }, {order_by => 'username'});
    return format_list($users, current_user => $viewer);
};

my $extra = sub {
    my ($object, $current_user) = @_;
    ouch(450, 'You must be an administrator to create a user.') unless $current_user->is_site_admin;
};

generate_options('User');
generate_read('User', permissions => ['view_my_account']);
generate_update('User', permissions => ['edit_my_account']);
generate_delete('User', permissions => ['edit_my_account']);
generate_create('User', extra_processing => $extra);
generate_all_relationships('User', permissions => ['view_my_account']);

get '/api/user/:id/firebase-jwt' => sub {
    my $user = fetch_object('User');
    my $current_user = get_user_by_session_id(permissions => ['edit_my_account']);
    $user->can_edit($current_user);
    my $firebase_config = Wing->config->get('firebase');
    return {
        jwt         => $user->firebase_jwt,
        id          => $firebase_config->{id},
        database    => $firebase_config->{database},
        api_key     => $firebase_config->{api_key},
    };
};

1;

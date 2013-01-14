package Wing::Web::Admin::User;

use Dancer ':syntax';
use Wing::Perl;
use Ouch;
use Wing;
use Wing::Web;

get '/admin/users' => sub {
    my $current_user = get_admin_by_session_id();
    template 'admin/users', { current_user => describe($current_user, current_user => $current_user) };
};

post '/admin/user' => sub {
    my $current_user = get_admin_by_session_id();
    my $object = site_db()->resultset('User')->new({});
    my %params = params;
    eval {
        $object->verify_creation_params(\%params, $current_user);
        $object->verify_posted_params(\%params, $current_user);
    };
    if ($@) {
        return redirect '/admin/users?error_message='.bleep;
    }
    else {
        $object->insert;
        return redirect '/admin/users?success_message=Created successfully.';
    }
};

get '/admin/user/:id' => sub {
    my $current_user = get_admin_by_session_id();
    template 'admin/user', { current_user => describe($current_user, current_user => $current_user), page_title => 'Edit User', user => describe(fetch_object('User'), current_user => $current_user)};
};

post '/admin/user/:id' => sub {
    my $current_user = get_admin_by_session_id();
    my $object = fetch_object('User');
    my %params = params;
    eval {
        $object->verify_creation_params(\%params, $current_user);
        $object->verify_posted_params(\%params, $current_user);
        if (params->{password1}) {
            if (params->{password1} eq params->{password2}) {
                $object->encrypt_and_set_password(params->{password1});
            }
            else {
                ouch 442, 'The passwords you typed do not match.', 'password';
            }
        }
    };
    if ($@) {
        template 'admin/user', { 
            error_message   => bleep,
            current_user    => $current_user, 
            user            => describe(fetch_object('User'), current_user => $current_user),
        };
    }
    else {
        $object->update;
        return redirect '/admin/users?success_message=Updated successfully.';
    }
};


post '/admin/user/:id/become' => sub {
    my $current_user = get_admin_by_session_id();
    my $object = fetch_object('User');
    my $session = $current_user->current_session;
    $session->user_id($object->id);
    $session->extend;
    set_cookie session_id   => $session->id,
                expires     => '+5y',
                http_only   => 0,
                path        => '/';
    return redirect '/account';
};

true;

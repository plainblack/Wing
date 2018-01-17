package Wing::Web::Account;

use Dancer ':syntax';
use Wing::Perl;
use Ouch;
use Wing;
use Wing::Web;
use Wing::SSO;
use Wing::Client;
use String::Random qw(random_string);
use Facebook::Graph;

require Wing::Dancer;

get '/login' => sub {
    template 'account/login';
};

post '/login' => sub {
    return template 'account/login', { error_message => 'You must specify a username or email address.'} unless params->{login};
    return template 'account/login', { error_message => 'You must specify a password.'} unless params->{password};
    my $username = params->{login};
    my $password = params->{password};
    my $user = site_db()->resultset('User')->search({email => $username },{rows=>1})->single;
    my @syncable_fields = qw/username email real_name use_as_display_name/;
    unless (defined $user) {
        $user = site_db()->resultset('User')->search({username => $username },{rows=>1})->single;
    }
    if (vars->{is_tenant} && Wing->config->get('tenants/sso_key')) {
        ##Tenant SSO logins and sync
        my $wing = Wing::Client->new( uri => Wing->config->get('tenants/sso_hostname') );
        if (! defined $user) {
            ##Do login check against remote.
            my $lookup = eval { $wing->post('session/tenantsso', { username => $username , password => $password, api_key => Wing->config->get('tenants/sso_key'), }); };
            if (hug) {
                Wing->log->warn('Error with tenant sso: '.$@);
                return template 'account/login', { error_message => $@};
            }
            else {
                $user = site_db()->resultset('User')->new({});
                $user->sync_with_remote_data($lookup, @syncable_fields);
                $user->master_user_id($lookup->{id});
                $user->insert;
                return login($user);
            }
        }
        else {
            if ($user->can('master_user_id') && $user->master_user_id) {
                ##Do login check against remote and sync
                my $lookup = eval { $wing->post('session/tenantsso', { user_id => $user->master_user_id, password => $password, api_key => Wing->config->get('tenants/sso_key'), }); };
                if (hug) {
                    Wing->log->warn('Error with tenant sso: '.$@);
                    return template 'account/login', { error_message => $@ };
                }
                else {
                    $user->sync_with_remote_data($lookup, @syncable_fields);
                    $user->update;
                    return login($user);
                }
            }
            else {
                ##Standard login check
                return standard_login_check($user, $password);
            }
        }
    }
    else {
        ##Local logins only!
        return standard_login_check($user, $password);
    }
};

sub standard_login_check {
    my $user = shift;
    my $password = shift;
    return template 'account/login', { error_message => 'User not found.'} unless defined $user;
    # validate password
    if ($user->is_password_valid($password)) {
        return login($user);
    }
    return template 'account/login', { error_message => 'Password incorrect.'};
}

any '/logout' => sub {
    my $session = get_session();
    if (defined $session) {
        $session->end;
    }
    #session->destroy; #enable if we start using dancer sessions
    return redirect params->{redirect_after} || '/login';
};

get '/account/apikeys' => sub {
    my $user = get_user_by_session_id();
    my $api_keys = $user->api_keys;
    template 'account/apikeys', {current_user => $user, apikeys => format_list($api_keys, current_user => $user) };
};

post '/account/apikey' => sub {
    my $current_user = get_user_by_session_id();
    my $object = site_db()->resultset('APIKey')->new({});
    $object->user($current_user);
    my %params = params;
    eval {
        $object->verify_creation_params(\%params, $current_user);
        $object->verify_posted_params(\%params, $current_user);
    };
    if (hug) {
        return redirect '/account/apikeys?error_message='.bleep;
    }
    else {
        $object->private_key(random_string('ssssssssssssssssssssssssssssssssssss'));
        $object->insert;
        return redirect '/account/apikeys?success_message=Created successfully.';
    }
};

get '/account/apikey/:id' => sub {
    my $current_user = get_user_by_session_id();
    my $api_key = fetch_object('APIKey');
    $api_key->can_view($current_user);
    template 'account/apikey', {
        current_user => $current_user,
        apikey => describe($api_key, current_user => $current_user),
    };
};

del '/account/apikey/:id' => sub {
    my $current_user = get_user_by_session_id();
    my $api_key = fetch_object('APIKey');
    $api_key->can_edit($current_user);
    $api_key->delete;
    redirect '/account/apikeys';
};


post '/account/apikey/:id' => sub {
    my $current_user = get_user_by_session_id();
    my $object = fetch_object('APIKey');
    $object->can_edit($current_user);
    my %params = params;
    eval {
        $object->verify_posted_params(\%params, $current_user);
    };
    if (hug) {
        return redirect '/account/apikey/'.$object->id.'?error_message='.bleep;
    }
    else {
        $object->update;
        return redirect '/account/apikeys?success_message=Updated successfully';
    }
};

get '/account' => sub {
    my $user = get_user_by_session_id();
    template 'account/index', { current_user => $user, };
};

post '/account' => sub {
    my $user = get_user_by_session_id();
    my %params = params;
    eval {
        $user->verify_posted_params(\%params, $user);
        if (params->{password1}) {
            if (params->{password1} eq params->{password2}) {
                $user->encrypt_and_set_password(params->{password1});
            }
            else {
                ouch 442, 'The passwords you typed do not match.', 'password';
            }
        }
    };
    if ($@) {
        redirect '/account?error_message='.bleep;
    }
    else {
        $user->update;
        login($user); # in case they changed their password
        redirect '/account?success_message=Updated successfully.';
    }
};

post '/account/create' => sub {
    my %params = params;
    my $user = site_db()->resultset('User')->new({});
    eval {
        $user->verify_creation_params(\%params, $user);
        $user->verify_posted_params(\%params, $user);
        if (params->{password1} eq params->{password2}) {
            $user->encrypt_and_set_password(params->{password1});
        }
        else {
            ouch 442, 'The passwords you typed do not match.', 'password';
        }
    };
    if ($@) {
        return template 'account/login', { error_message => bleep };
    }
    $user->insert;
    return login($user);
};

get '/account/reset-password' => sub {
    template 'account/reset-password';
};

post '/account/reset-password' => sub {
    return template 'account/reset-password', {error_message => 'You must supply an email address or username.'} unless params->{login};
    my $user = site_db()->resultset('User')->search({username => params->{login}},{rows=>1})->single;
    unless (defined $user) {
        $user = site_db()->resultset('User')->search({email => params->{login}},{rows=>1})->single;
        return template 'account/reset-password', {error_message => 'User not found.'} unless defined $user;
    }
    if ($user->permanently_deactivated) {
        return template 'account/reset-password', {error_message => 'Account permanently deactivated.'};
    }

    # validate password
    if ($user->email) {
        my $code = $user->generate_password_reset_code();
        $user->send_templated_email(
            'reset_password',
            {
                code        => $code,
            }
        );
        return redirect '/account/reset-password-code';
    }
    return template 'account/reset-password', {error_message => 'That account has no email address associated with it.'};
};

get '/account/reset-password-code' => sub {
    template 'account/reset-password-code';
};

post '/account/reset-password-code' => sub {
    return template 'account/reset-password-code', {error_message => 'You must supply a reset code.'} unless params->{code};
    return template 'account/reset-password-code', {error_message => 'You must supply a new password.'} unless params->{password1};
    if (params->{password1} ne params->{password2}) {
        return template 'account/reset-password-code', {error_message => 'The passwords you typed do not match.'};
    }

    my $user_id = Wing->cache->get('password_reset'.params->{code});
    unless ($user_id) {
        return template 'account/reset-password-code', {error_message => 'That is an invalid code.'};
    }
    my $user = site_db()->resultset('User')->find($user_id);
    unless (defined $user) {
        return template 'account/reset-password-code', {error_message => 'The user attached to that code no longer exists.'};
    }
    if ($user->permanently_deactivated) {
        return template 'account/reset-password', {error_message => 'Account permanently deactivated.'};
    }
    $user->encrypt_and_set_password(params->{password1});
    return login($user);
};

get '/sso' => sub {
    my $user = eval{ get_user_by_session_id() };
    unless (params->{api_key_id}) {
        ouch 441, 'api_key_id is required.', 'api_key_id';
    }
    unless (params->{postback_uri}) {
        ouch 441, 'postback_uri is required.', 'postback_uri';
    }
    my $api_key = site_db()->resultset('APIKey')->find(params->{api_key_id});
    unless (defined $api_key) {
        ouch 440, 'API Key not found.', 'api_key_id';
    }
    my $permissions = params->{permission};
    unless (ref $permissions eq 'ARRAY') {
        $permissions = [$permissions];
    }
    my $sso = Wing::SSO->new(
        api_key_id              => $api_key->id,
        ip_address              => request->remote_address,
        postback_uri            => params->{postback_uri},
        requested_permissions   => $permissions,
        db                      => site_db(),
    )->store;
    if (defined $user) {
        if ($user->permanently_deactivated) {
            ouch 442, 'Account permanently deactivated';
        }
        $sso->user_id($user->id);
        $sso->store;
        if ($sso->has_requested_permissions) {
            return redirect $sso->redirect;
        }
        else {
            return redirect '/sso/authorize?sso_id='.$sso->id;
        }
    }
    template 'account/login', {sso_id => $sso->id};
};

get '/sso/authorize' => sub {
    my $user = get_user_by_session_id();
    if ($user->permanently_deactivated) {
        ouch 442, 'Account permanently deactivated';
    }
    my $sso = Wing::SSO->new(id => params->{sso_id}, db => site_db());
    ouch(401, 'User does not match SSO token.') unless $user->id eq $sso->user_id;
    template 'account/authorize', {
        current_user            => $user,
        sso_id                  => $sso->id,
        requested_permissions   => $sso->requested_permissions,
        api_key                 => $sso->api_key->describe,
    };
};

post '/sso/authorize' => sub {
    my $user = get_user_by_session_id();
    if ($user->permanently_deactivated) {
        ouch 442, 'Account permanently deactivated';
    }
    my $sso = Wing::SSO->new(id => params->{sso_id}, db => site_db());
    $sso->grant_requested_permissions;
    return redirect $sso->redirect;
};

get '/sso/success' => sub {
    my $user = get_user_by_session_id();
    template 'account/ssosuccess', {
        current_user            => $user,
    };
};

get '/account/facebook' => sub {
    if (params->{sso_id}) {
        set_cookie sso_id  => params->{sso_id};
    }
    if (params->{redirect_after}) {
        set_cookie redirect_after  => params->{redirect_after};
    }
    redirect facebook()->authorize->extend_permissions(qw(email))->uri_as_string;
};

get '/account/facebook/postback' => sub {
    my $fb = facebook();
    $fb->request_access_token(params->{code});
    my $fbuser = $fb->query->find('me')->request->as_hashref;

    unless (exists $fbuser->{id}) {
        ouch 401, 'Could not authenticate your Facebook account.';
    }

    my $user = eval { get_user_by_session_id() };
    if (defined $user) {
        if ($user->permanently_deactivated) {
            ouch 442, 'Account permanently deactivated';
        }
        $user->facebook_uid($fbuser->{id});
        $user->update;
    }

    my $users = site_db()->resultset('User');
    $user = $users->search({facebook_uid => $fbuser->{id} }, { rows => 1 })->single;
    if (exists $fbuser->{email}) {
        if (defined $user) {
            $user->email($fbuser->{email}); # update their email in case it's changed
            $user->update;
        }
        else {
            $user = $users->search({email => $fbuser->{email} }, { rows => 1 })->single;
            if (defined $user) { # an account with that email already exists, let's link it to facebook
                $user->facebook_uid($fbuser->{id});
                $user->update;
            }
            else { # create a new account
                $user = $users->new({});
                $user->facebook_uid($fbuser->{id});
                $user->real_name($fbuser->{name});
                $user->email($fbuser->{email});
                $user->username($fbuser->{email});
                $user->insert;
            }
        }
    }
    elsif (! defined $user) {
        return template 'account/finish_facebook', { facebook => $fbuser };
    }
    return login($user);
};

get '/account/profile/:id' => sub {
    my $current_user = eval{get_user_by_session_id()};
    my $user = fetch_object('User');
    template 'account/profile', {
        current_user    => $current_user,
        profile_user    => describe($user, current_user => $current_user),
    };
};

sub facebook {
    return Facebook::Graph->new(Wing->config->get('facebook'));
}

true;

package Wing::Rest::Session;

use Wing::Perl;
use Ouch;
use Wing::Session;
use Dancer;
use Wing::Rest;
use Wing::SSO;

del '/api/session/:id' => sub {
    Wing::Session->new(id => params->{id}, db => MobRaterManager->db, cache => MobRaterManager->cache)->end;
    return { success => 1 };
};

post '/api/session/sso/:id' => sub {
    unless (params->{private_key}) {
        ouch 441, 'Private Key required.', 'private_key';
    }
    my $sso = Wing::SSO->new(id => params->{id}, db => vars->{site_db}, cache => MobRaterManager->cache);
    unless ($sso->api_key_id) {
        ouch 440, 'SSO token not found.';
    }
    unless ($sso->api_key->private_key eq params->{private_key}) {
        ouch 454, 'Private key does not match SSO token.';
    }
    return describe($sso->user->start_session({ip_address => request->remote_address, api_key_id => $sso->api_key_id, sso => 1}));
};

get '/api/session/:id' => sub {
    my $session = get_session(params->{id});
    return describe($session);
};

post '/api/session' => sub {
    ouch(441, 'You need an API key.', 'api_key_id') unless params->{api_key_id};
    ouch(441, 'You must specify a username.', 'username') unless params->{username};
    ouch(441, 'You must specify a password.', 'password') unless params->{password};
    my $user = vars->{site_db}->resultset('User')->search({username => params->{username}},{rows=>1})->single;
    ouch(440, 'User not found.') unless defined $user;

    # rate limiter
    my $max = MobRaterManager->config->get('rpc_limit') || 30;
    if ($user->rpc_count > $max) {
        ouch 452, 'Slow down! You are only allowed to make ('.$max.') requests per minute to the server.';
    }
    
    # is developer
    unless ($user->is_developer) { 
        ouch 453, 'This user is not a developer.';
    }

    # validate password
    if ($user->is_password_valid(params->{password})) {
        my $session = $user->start_session({ api_key_id => params->{api_key_id}, ip_address => request->remote_address });
        return describe($session, $user);
    }
    else {
        ouch 454, 'Password incorrect.';
    }
};



1;

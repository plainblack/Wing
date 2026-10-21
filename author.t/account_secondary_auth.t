use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib", "$FindBin::Bin/../lib";
use Test::More;
BEGIN {
    package AccountAuthConfig;
    our $browser_key = 'browser-api';
    sub get { $_[1] eq 'default_api_key' ? $browser_key : undef }
    package Wing;
    sub config { bless {}, 'AccountAuthConfig' }
    $INC{'Wing.pm'} = __FILE__;
}
use TestWing::DB::Result::User;
use Wing;
use Wing::Session;

{
    package AccountAuthCache;
    sub new { bless {}, shift }
    sub get { $_[0]->{$_[1]} }
    sub set { $_[0]->{$_[1]} = $_[2]; 1 }
}

my $cache = AccountAuthCache->new;
{
    no warnings qw(redefine once);
    local *Wing::cache = sub { $cache };
    my $user = TestWing::DB::Result::User->new({
        id => 'account-user', real_name => 'Original name', admin => 0, password => 'original-hash',
    });
    my $session = Wing::Session->new(id => 'browser-session', db => bless({}, 'AccountAuthDatabase'));
    $session->api_key_id(Wing->config->get('default_api_key'));
    $user->current_session($session);

    my $accepted = eval { $user->verify_posted_params({ real_name => 'Changed name' }, $user); 1 };
    ok(!$accepted, 'unverified browser session cannot change its account');
    my $error = $@;
    is(eval { $error->code }, 450, 'account update reports an authorization error');
    is(eval { $error->data }, 'secondary_authentication', 'account update identifies required verification');
    is($user->real_name, 'Original name', 'rejected update does not change account fields');

    eval { $user->verify_posted_params({ password => 'replacement-password' }, $user) };
    is($user->password, 'original-hash', 'verification runs before password mutation');

    $user->mark_secondary_auth_verified;
    $user->verify_posted_params({ real_name => 'Verified name' }, $user);
    is($user->real_name, 'Verified name', 'verified browser session can update its account');

    {
        local $AccountAuthConfig::browser_key = undef;
        my $browser_user = TestWing::DB::Result::User->new({ id => 'browser-without-key', real_name => 'Original name', admin => 0 });
        $browser_user->current_session(Wing::Session->new(id => 'browser-without-key', db => bless({}, 'AccountAuthDatabase')));
        eval { $browser_user->verify_posted_params({ real_name => 'Unverified name' }, $browser_user) };
        is($browser_user->real_name, 'Original name', 'browser login without a configured default key still requires verification');
    }

    for my $case (
        ['independent API key', 'developer-api', 0],
        ['SSO grant', 'browser-api', 1],
    ) {
        my ($name, $api_key, $sso) = @$case;
        my $client = TestWing::DB::Result::User->new({ id => $name, real_name => 'Original name', admin => 0 });
        my $client_session = Wing::Session->new(id => $name, db => bless({}, 'AccountAuthDatabase'));
        $client_session->api_key_id($api_key);
        $client_session->sso($sso);
        $client->current_session($client_session);
        ok(!$client->has_secondary_auth_token, "$name has no browser verification");
        $client->verify_posted_params({ real_name => 'Client name' }, $client);
        is($client->real_name, 'Client name', "$name retains its account-update contract");
    }

    my $admin = TestWing::DB::Result::User->new({ id => 'admin-user', real_name => 'Admin name', admin => 1 });
    $admin->current_session($session);
    eval { $admin->verify_posted_params({ real_name => 'Unverified admin' }, $admin) };
    is($admin->real_name, 'Admin name', 'administrator must verify browser edits to their own account');
    $user->verify_posted_params({ real_name => 'Managed name' }, $admin);
    is($user->real_name, 'Managed name', 'administrator editing another user retains existing permissions');

    my $created = TestWing::DB::Result::User->new({ real_name => 'New account', admin => 0 });
    $created->verify_posted_params({ real_name => 'Created name' }, $admin);
    is($created->real_name, 'Created name', 'new account validation retains existing permissions');
}

done_testing;

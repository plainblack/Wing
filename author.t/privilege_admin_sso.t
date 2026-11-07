use strict;
use warnings;
use Test::More;
use Wing;

my $users = Wing->db->resultset('User');
my $admin = $users->create({username => 'priv-admin', email => 'priv-admin@example.invalid', admin => 1});
my $developer = $users->create({username => 'priv-dev', email => 'priv-dev@example.invalid', developer => 1});
my $key = $admin->apikeys->create({name => 'priv-admin-client'});
my $dev_key = $developer->apikeys->create({name => 'priv-dev-client'});

my $admin_sso = $admin->start_session({sso => 1, api_key_id => $key->id})->user;
ok !$admin_sso->is_developer, 'an admin SSO session does not get privileges through the admin bypass';
is eval { $admin_sso->verify_is_developer; 200 } // $@->code, 450, 'verify_is_developer refuses an admin SSO session with 450';
ok $admin->start_session({sso => 0})->user->is_developer, 'an admin site session keeps the admin bypass';
ok $developer->start_session({sso => 1, api_key_id => $dev_key->id})->user->is_developer, 'an SSO session keeps privileges the user has';

done_testing();

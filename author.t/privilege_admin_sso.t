use strict;
use warnings;
use Test::More;
use Wing;

my $users = Wing->db->resultset('User');
my $admin = $users->create({username => 'priv-admin', email => 'priv-admin@example.invalid', admin => 1});
my $holder = $users->create({username => 'priv-holder', email => 'priv-holder@example.invalid', developer => 1, auditor => 1});
my $admin_key = $admin->apikeys->create({name => 'priv-admin-client'});
my $holder_key = $holder->apikeys->create({name => 'priv-holder-client'});
my $code = sub { my $method = shift; eval { $_[0]->$method; 200 } // $@->code };

# start_session sets the session on the object it is called on, so each session gets its own copy of the user.
my $as = sub { my ($user, %session) = @_; $user->get_from_storage->start_session(\%session)->user };
my %app = (admin => $as->($admin, sso => 1, api_key_id => $admin_key->id), holder => $as->($holder, sso => 1, api_key_id => $holder_key->id));
my %site = (admin => $as->($admin, sso => 0), holder => $as->($holder, sso => 0));

is $code->('verify_is_admin', $app{admin}), 450, 'verify_is_admin refuses an admin app session';
like eval { $app{admin}->verify_is_admin; '' } // $@->message, qr/site session/, 'the refusal tells the user to log in with a site session';
is $code->('verify_is_admin', $site{admin}), 200, 'verify_is_admin accepts an admin site session';
is $code->('verify_is_admin', $app{holder}), 450, 'verify_is_admin still refuses a non-admin';

for my $who (qw(admin holder)) {
    ok $app{$who}->is_developer, "is_developer is true for the $who app session";
    is $code->('verify_is_developer', $app{$who}), 200, "verify_is_developer without the opt-in accepts the $who app session";
    ok !$app{$who}->is_auditor, "is_auditor with the opt-in is false for the $who app session";
    ok $site{$who}->is_auditor, "is_auditor with the opt-in is true for the $who site session";
    is $code->('verify_is_auditor', $app{$who}), 450, "verify_is_auditor with the opt-in refuses the $who app session";
    is $code->('verify_is_auditor', $site{$who}), 200, "verify_is_auditor with the opt-in accepts the $who site session";
}
is $code->('verify_is_auditor', $users->create({username => 'priv-none', email => 'priv-none@example.invalid'})), 450,
    'verify_is_auditor still refuses a user without the privilege';

done_testing();

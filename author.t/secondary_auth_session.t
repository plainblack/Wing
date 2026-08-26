use strict;
use warnings;
use Test::More;
use lib 'author.t/lib', 'lib';
use Wing::Role::Result::User;

{
    package Local::SecondaryAuthCache;

    sub new { return bless { values => {} }, shift }

    sub get {
        my ($self, $key) = @_;
        return $self->{values}{$key};
    }

    sub set {
        my ($self, $key, $value) = @_;
        $self->{values}{$key} = $value;
        return 1;
    }
}

{
    package Local::SecondaryAuthSession;

    sub new { return bless { id => $_[1] }, $_[0] }
    sub id { return $_[0]->{id} }
}

{
    package Local::SecondaryAuthUser;

    sub new {
        my ($class, $session_id) = @_;
        return bless {
            id      => 'user-1',
            session => Local::SecondaryAuthSession->new($session_id),
        }, $class;
    }

    sub id { return $_[0]->{id} }
    sub has_current_session { return 1 }
    sub current_session { return $_[0]->{session} }
    sub secondary_auth_cache_key { return Wing::Role::Result::User::secondary_auth_cache_key(@_) }
    sub has_secondary_auth_token { return Wing::Role::Result::User::has_secondary_auth_token(@_) }
    sub mark_secondary_auth_verified { return Wing::Role::Result::User::mark_secondary_auth_verified(@_) }
    sub verify_secondary_auth { return Wing::Role::Result::User::verify_secondary_auth(@_) }
}

my $cache = Local::SecondaryAuthCache->new;
my $first_session = Local::SecondaryAuthUser->new('session-1');
my $second_session = Local::SecondaryAuthUser->new('session-2');

{
    no warnings qw(redefine once);
    local *Wing::cache = sub { return $cache };

    ok(!$first_session->has_secondary_auth_token, 'first session starts unverified');
    ok(!$second_session->has_secondary_auth_token, 'second session starts unverified');

    ok($first_session->mark_secondary_auth_verified, 'marks the first session verified');
    ok($first_session->has_secondary_auth_token, 'first session is verified');
    ok(!$second_session->has_secondary_auth_token, 'verification does not carry into another login');

    $cache->set($first_session->secondary_auth_cache_key('verify'), 'email-token');
    ok(!$second_session->verify_secondary_auth('email-token'), 'email token is limited to the requesting session');
}

done_testing;

use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Wing;
use Wing::Rest;
use Plack::Test;
use Dancer::Handler;
use HTTP::Request::Common qw(GET);
use JSON qw(decode_json);

set show_errors => 0;
set behind_proxy => 0;
sub make_user {
    my ($name) = @_;
    my $user = Wing->db->resultset('User')->new({username => $name, email => $name.'@example.invalid'});
    $user->encrypt_and_set_password('cache-password');
    $user->insert;
    return $user;
}
get '/cache-probe' => sub { return get_user_by_session_id()->id };

my $user_queries = 0;
Wing->db->storage->debugcb(sub { $user_queries++ if $_[1] =~ /\bFROM\s+`?users`?/i });
Wing->db->storage->debug(1);
my $app = Dancer::Handler->get_handler->psgi_app;
test_psgi $app, sub {
    my $request = shift;
    my $probe = sub {
        my ($session) = @_;
        $user_queries = 0;
        return $request->(GET 'http://localhost/cache-probe', Cookie => 'session_id='.$session->id);
    };
    my $refused = sub {
        my ($sessions, $name) = @_;
        for my $i (0 .. $#$sessions) {
            is $probe->($sessions->[$i])->code, 401, "$name ends session $i";
        }
    };
    my $warm = sub {
        my ($user) = @_;
        my @sessions = map { $user->start_session({}) } 1, 2;
        $probe->($_) for @sessions;
        for my $session (@sessions) {
            is decode_json($probe->($session)->content)->{result}, $user->id, "session resolves its user";
            is $user_queries, 0, "a repeat request reads its user from the session cache";
        }
        return \@sessions;
    };

    my $user = make_user('cache-password');
    my $sessions = $warm->($user);
    $user->encrypt_and_set_password('changed-password');
    $user->update;
    $refused->($sessions, 'password change');

    $user = make_user('cache-deactivated');
    $sessions = $warm->($user);
    $user->deactivate;
    $refused->($sessions, 'deactivation');

    $user = make_user('cache-deleted');
    $sessions = $warm->($user);
    $user->delete;
    $refused->($sessions, 'deletion');

    $user = make_user('cache-evicted');
    $sessions = $warm->($user);
    Wing->cache->remove('user-changed-'.$user->id);
    is $probe->($sessions->[0])->code, 200, 'a session without a change marker still resolves';
    ok $user_queries, 'a missing change marker reloads the user from the database';

    # A second connection holds the password change uncommitted while a session refreshes.
    $user = make_user('cache-transaction');
    $sessions = $warm->($user);
    my $writer = ref(Wing->db)->connect(@{Wing->config->get('db')});
    $writer->txn_begin;
    $writer->resultset('User')->find($user->id)->encrypt_and_set_password('changed-password')->update;
    is $probe->($sessions->[0])->code, 200, 'an uncommitted password change does not end the session yet';
    $writer->txn_commit;
    $refused->($sessions, 'committed transactional password change');
};

done_testing;

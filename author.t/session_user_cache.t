use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Wing;
use Wing::Rest;
use Wing::Session;
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
    # A real change writes the marker; a login in the same second as creation leaves last_login unchanged.
    $user->update({real_name => $name});
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

    # A no-op update during the open transaction must not replace its uncommitted marker.
    $user = make_user('cache-noop');
    $sessions = $warm->($user);
    $writer->txn_begin;
    $writer->resultset('User')->find($user->id)->encrypt_and_set_password('changed-password')->update;
    Wing->db->resultset('User')->find($user->id)->update;
    is $probe->($sessions->[0])->code, 200, 'an uncommitted password change with a no-op update does not end the session yet';
    $writer->txn_commit;
    $refused->($sessions, 'committed password change after a no-op update');

    # A request that began before the change writes its older session entry after this one was read.
    $user = make_user('cache-pair');
    $user->admin(1);
    $user->update;
    $sessions = $warm->($user);
    my $older = Wing->cache->get($sessions->[0]->key);
    $user->admin(0);
    $user->update;
    $probe->($sessions->[0]);
    my $loaded = Wing::Session->new(id => $sessions->[0]->id, db => Wing->db);
    Wing->cache->set($sessions->[0]->key, $older);
    ok !$loaded->user->admin, 'a session uses the user data it read with its change marker';
};

done_testing;

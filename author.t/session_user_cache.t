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
    my $user = Wing->db->resultset('User')->new({username => $name, email => $name.'@example.invalid', real_name => 'before'});
    $user->encrypt_and_set_password('cache-password');
    $user->insert;
    return $user;
}
get '/cache-probe' => sub { my $user = get_user_by_session_id(); return { id => $user->id, real_name => $user->real_name } };

my $user_queries = 0;
my $on_user_query;
Wing->db->storage->debugcb(sub {
    return unless $_[1] =~ /\bFROM\s+`?users`?/i;
    $user_queries++;
    $on_user_query->() if $on_user_query;
});
Wing->db->storage->debug(1);
my $app = Dancer::Handler->get_handler->psgi_app;
test_psgi $app, sub {
    my $request = shift;
    my $probe = sub {
        my ($session) = @_;
        $user_queries = 0;
        return $request->(GET 'http://localhost/cache-probe', Cookie => 'session_id='.$session->id);
    };
    my $name = sub { decode_json($probe->($_[0])->content)->{result}{real_name} };
    my $refused = sub {
        my ($sessions, $label) = @_;
        for my $i (0 .. $#$sessions) {
            is $probe->($sessions->[$i])->code, 401, "$label ends session $i";
        }
    };
    # Stands in for the change marker's expiry.
    my $expire_marker = sub { Wing->cache->remove('user-changed-'.$_[0]->id) };
    my $warm = sub {
        my ($user) = @_;
        my @sessions = map { $user->start_session({}) } 1, 2;
        $expire_marker->($user); # login updates last_login
        $probe->($_) for @sessions;
        for my $session (@sessions) {
            is decode_json($probe->($session)->content)->{result}{id}, $user->id, 'session resolves its user';
            is $user_queries, 0, 'a repeat request reads its user from the cache';
        }
        return \@sessions;
    };

    my $user = make_user('cache-untouched');
    my $sessions = $warm->($user);

    $user->update({real_name => 'after'});
    is $name->($_), 'after', 'a session sees the updated user' for @$sessions;
    $expire_marker->($user);
    $name->($sessions->[0]);
    is $name->($sessions->[1]), 'after', 'the cache holds the updated user once the marker expires';
    is $user_queries, 0, 'the updated user is cached again once the marker expires';

    $user = make_user('cache-password');
    $sessions = $warm->($user);
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
    Wing->cache->remove('user-data-'.$user->id);
    is $probe->($sessions->[0])->code, 200, 'a session whose cached user was evicted still resolves';
    ok $user_queries, 'an evicted user is reloaded from the database';

    # Another application changes the row and writes only the marker, then removes it.
    $user = make_user('cache-foreign');
    $sessions = $warm->($user);
    Wing->db->resultset('User')->search({id => $user->id})->update({real_name => 'foreign'});
    Wing->cache->set('user-changed-'.$user->id, 1);
    is $name->($sessions->[0]), 'foreign', 'any truthy marker reloads the user';
    $expire_marker->($user);
    is $name->($sessions->[1]), 'foreign', 'a marker seen once drops the cached user';

    # A change commits while a request reads the old row, before it caches that row.
    $user = make_user('cache-race');
    $sessions = $warm->($user);
    Wing->cache->remove('user-data-'.$user->id);
    $on_user_query = sub { Wing->cache->set('user-changed-'.$user->id, 1) };
    $probe->($sessions->[0]);
    undef $on_user_query;
    ok !defined Wing->cache->get('user-data-'.$user->id), 'a row read during a change is not left cached';

    # A second connection holds the password change uncommitted while a session refreshes.
    $user = make_user('cache-transaction');
    $sessions = $warm->($user);
    my $writer = ref(Wing->db)->connect(@{Wing->config->get('db')});
    $writer->txn_begin;
    $writer->resultset('User')->find($user->id)->encrypt_and_set_password('changed-password')->update;
    is $probe->($sessions->[0])->code, 200, 'an uncommitted password change does not end the session yet';
    $writer->txn_commit;
    $refused->($sessions, 'committed transactional password change');

    $user = make_user('cache-rollback');
    $sessions = $warm->($user);
    $writer->txn_begin;
    $writer->resultset('User')->find($user->id)->update({real_name => 'rolled back'});
    is $name->($sessions->[0]), 'before', 'an uncommitted change is not served';
    $writer->txn_rollback;
    is $name->($sessions->[1]), 'before', 'a rolled back change is not served';
    $expire_marker->($user);
    $name->($sessions->[0]);
    is $name->($sessions->[1]), 'before', 'a rolled back change does not poison the cache';
    is $user_queries, 0, 'the committed user is cached again after a rollback';
};

done_testing;

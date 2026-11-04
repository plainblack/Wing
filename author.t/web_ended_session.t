use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Dancer::Test;
use Wing;
use Wing::Web;

set show_errors => 0;
get '/ended-session-probe' => sub { return defined get_session() ? 'live' : 'none' };
my $helper_input;
get '/helper-input-probe' => sub {
    my $user = eval { get_user_by_session_id(session_id => $helper_input) };
    return defined $user ? 'user '.$user->id : 'error '.(ref $@ eq 'Ouch' ? $@->code : $@);
};
sub helper_probe { $helper_input = shift; return dancer_response(GET => '/helper-input-probe')->content }
sub make_session {
    my ($name) = @_;
    my $user = Wing->db->resultset('User')->new({username => $name, email => $name.'@example.invalid'});
    $user->encrypt_and_set_password('web-ended-password');
    $user->insert;
    return ($user, $user->start_session({auth_source => 'site', absolute_expires_at => time + 4 * 60 * 60}));
}
sub probe {
    my ($session) = @_;
    return dancer_response(GET => '/ended-session-probe', {params => {session_id => $session->id}})->content;
}

my ($expired_user, $expired) = make_session('web-ended-expired');
my $data = Wing->cache->get($expired->key);
$data->{absolute_expires_at} = time - 60;
Wing->cache->set($expired->key, $data);
is probe($expired), 'none', 'web get_session denies an absolute-expired session';

my ($changed_user, $changed) = make_session('web-ended-password');
$changed_user->encrypt_and_set_password('changed-password');
$changed_user->update;
is probe($changed), 'none', 'web get_session denies a password-changed session';

my ($active_user, $active) = make_session('web-ended-active');
is probe($active), 'live', 'web get_session returns an active session';

is helper_probe($active), 'user '.$active_user->id, 'a session object resolves its user';
is helper_probe($active_user), 'error 401', 'a user object is not accepted as a session';
$active->end;
is helper_probe($active), 'error 401', 'an ended session object is refused';

my ($held_user, $held) = make_session('web-ended-held');
Wing::Session->new(id => $held->id, db => Wing->db)->end;
is helper_probe($held), 'error 401', 'a held session object ended through another instance is refused';

my ($rekeyed_user, $rekeyed) = make_session('web-ended-object-password');
$rekeyed_user->encrypt_and_set_password('changed-password');
$rekeyed_user->update;
is helper_probe($rekeyed), 'error 401', 'a password-changed session object is refused';

done_testing;

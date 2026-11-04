use strict;
use warnings;
use Test::More import => ['!pass'];
use Dancer ':syntax';
use Dancer::Test;
use Wing;
use Wing::Web;

set show_errors => 0;
get '/ended-session-probe' => sub { return defined get_session() ? 'live' : 'none' };
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

done_testing;

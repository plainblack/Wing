package Wing::Rest::User;

use Wing::Perl;
use Dancer;
use Ouch;
use Wing::Rest;

get '/api/user' => sub {
    ouch(450, 'You must be an administrator to get a list of all users.') unless get_user_by_session_id()->is_admin;
    my $users = site_db()->resultset('User')->search(undef,{order_by => 'username'});
    return format_list($users); 
};

my $extra = sub {
    my ($object, $current_user) = @_;
    ouch(450, 'You must be an administrator to create a user.') unless $current_user->is_admin;
};

generate_options('User');
generate_read('User');
generate_update('User');
generate_delete('User');
generate_create('User', $extra);

1;

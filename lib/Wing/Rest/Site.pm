package Wing::Rest::Site;

use Wing::Dancer;
use Wing::Perl;
use Dancer;
use Wing::Dancer;
use Ouch;
use Wing::Rest;

generate_options('Site');
generate_create('Site');
generate_read('Site');
generate_update('Site');

del '/api/site/:id'  => sub {
    my $object = fetch_object('Site');
    $object->can_edit(get_user_by_session_id());
    $object->trash;
    return { success => 1 };
};

put '/api/site/:id/restore' => sub {
    my $object = fetch_object('Site');
    $object->can_edit(get_user_by_session_id());
    $object->restore;
    return { success => 1 };
};

get '/api/sites' => sub {
    my $current_user = get_user_by_session_id();
    my $sites = Wing->db->resultset('Site')->search({user_id => $current_user->id, });
    return format_list($sites, $current_user);
};

1;

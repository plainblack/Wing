package Wing::Rest::Site;

use Wing::Perl;
use Dancer;
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

1;

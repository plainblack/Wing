package Wing::Rest::WebHook;

use Wing::Perl;
use Dancer;
use Wing::Rest;
use JSON qw(from_json);

post '/api/webhook/:id/test' => sub {
    my $user = get_user_by_session_id();
    my $hook = fetch_object('WebHook');
    $hook->can_edit($user);
    $hook->test(from_json(param('payload')));
};

my $extra = sub {
    my ($self, $current_user) = @_;
    my $object = fetch_object($self->owner_class, $self->owner_id);
    $object->can_edit($current_user);
};
generate_create('WebHook', permissions => ['edit_my_webhooks'], extra_processing => $extra);
generate_read('WebHook', permissions => ['edit_my_webhooks']);
generate_update('WebHook', permissions => ['edit_my_webhooks']);
generate_delete('WebHook', permissions => ['edit_my_webhooks']);
generate_all_relationships('WebHook');

1;

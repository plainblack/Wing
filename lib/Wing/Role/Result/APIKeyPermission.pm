package Wing::Role::Result::APIKeyPermission;

use Wing::Perl;
use Ouch;
use Moose::Role;
with 'Wing::Role::Result::Field';
with 'Wing::Role::Result::UserControlled';

before wing_finalize_class => sub {
    my ($class) = @_;
    $class->wing_field(
        permission                  => {
            dbic                => { data_type => 'varchar', size => 30, is_nullable => 0 },
            view                => 'private',
            edit                => 'postable',
            options             => Wing->config->get('api_key_permissions'),
        }
    );
};

after sqlt_deploy_hook => sub {
    my ($self, $sqlt_table) = @_;
    $sqlt_table->add_index(name => 'idx_apikey_user', fields => ['api_key_id','user_id']);
};

1;

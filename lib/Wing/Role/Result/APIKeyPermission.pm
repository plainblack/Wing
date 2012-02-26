package Wing::Role::Result::APIKeyPermission;

use Wing::Perl;
use Wing;
use Ouch;
use Moose::Role;
with 'Wing::Role::Result::Field';
with 'Wing::Role::Result::UserControlled';

around table => sub {
    my ($orig, $class, $table) = @_;
    $orig->($class, $table);
    $class->register_field(
        permisison                  => {
            dbic                => { data_type => 'varchar', size => 30, is_nullable => 0 },
            view                => 'private',
            edit                => 'postable',
            options             => Wing->config->get('api_key_permissions'),
        }
    );
};

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;
    $sqlt_table->add_index(name => 'idx_apikey_user', fields => ['api_key_id','user_id']);
}

1;

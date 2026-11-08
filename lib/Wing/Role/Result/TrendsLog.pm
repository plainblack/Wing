package Wing::Role::Result::TrendsLog;

use Wing::Perl;
use Ouch;
use Moose::Role;
with 'Wing::Role::Result::Field';

before wing_finalize_class => sub {
    my ($class) = @_;
    $class->wing_fields(
        name => {
            dbic 		=> { data_type => 'varchar', size => 60, is_nullable => 0 },
            view		=> 'public',
            edit		=> 'required',
            indexed     => 1,
        },
        value => {
            dbic 		=> { data_type => 'float', size => [15,2],  is_nullable => 0 },
            view		=> 'public',
            edit		=> 'required',
        },
        note => {
            dbic 		=> { data_type => 'text',  is_nullable => 1 },
            view		=> 'public',
            edit		=> 'postable',
        },
    );
};

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;
    $sqlt_table->add_index(name => 'idx_date_name_value', fields => ['date_created','name','value']);
}

sub trend_deltas {
    return {
        users_total => sub { Wing->db->resultset('User')->count }, 
        users_total_developers => sub { Wing->db->resultset('User')->search({developer => 1})->count },
    };
}

1;

package Wing::Role::Result::Site;

use Wing::Perl;
use Ouch;
use Moose::Role;
with 'Wing::Role::Result::Field';
with 'Wing::Role::Result::Shortname';
with 'Wing::Role::Result::Hostname';
with 'Wing::Role::Result::UserControlled';

around table => sub {
    my ($orig, $class, $table) = @_;
    $orig->($class, $table);
    $class->register_fields(
        name    => {
            dbic    => { data_type => 'varchar', size => 30, is_nullable => 0 },
            view    => 'public',
            edit    => 'required',
        },
        trashed                 => {
            dbic    => { data_type => 'tinyint', default_value => 0 },
        },
    );
};

around sqlt_deploy_hook => sub {
    my ($orig, $self, $sqlt_table) = @_;
    $orig->($self, $sqlt_table);
    $sqlt_table->add_index(name => 'idx_find_by_shortname', fields => ['shortname','trashed']);
    $sqlt_table->add_index(name => 'idx_find_by_hostname', fields => ['hostname','trashed']);
};

after insert => sub {
    my ($self) = @_;
    $self->create_database;
};

before delete => sub {
    my ($self) = @_;
    $self->destroy_database;
};

sub trash {
    my $self = shift;
    $self->trashed(1);
    $self->hostname(undef);
    $self->update;
}

sub connect_to_database {
    my $self = shift;
    my $config = MobRaterManager->config;
    my @dsn = @{$config->get('db')};
    $dsn[0] = $config->get('site_db_driver/prefix') . $self->shortname . $config->get('site_db_driver/suffix');
    return MobRater::DB->connect(@dsn);
}

sub create_database {
    my $self = shift;
    my $dbh = MobRaterManager->db->storage->dbh;
    $dbh->do("create database if not exists ".$dbh->quote_identifier($self->shortname));
    my $db = $self->connect_to_database;
    $db->deploy({ add_drop_table => 1 });
    $db->storage->disconnect;
}

sub destroy_database {
    my $self = shift;
    my $dbh = MobRaterManager->db->storage->dbh;
    $dbh->do("drop database if exists ".$dbh->quote_identifier($self->shortname));
}

1;

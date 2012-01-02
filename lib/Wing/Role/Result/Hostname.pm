package Wing::Role::Result::Hostname;

use Wing::Perl;
use Ouch;
use Moose::Role;

around table => sub {
    my ($orig, $class, $table) = @_;
    $orig->($class, $table);
    $class->add_columns(
        hostname        => { data_type => 'varchar', size => 255, is_nullable => 0 },
    );
    $class->meta->add_before_method_modifier('hostname', sub {
        my ($self, $name) = @_;
        if ($name) {
            ouch(442, 'Hostname cannot contain upper case characters.', 'hostname') if $name =~ m/[A-Z]/;
            ouch(442, 'Hostname cannot contain spaces.', 'hostname') if $name =~ m/\s/;
            ouch(442, 'Hostname must start with an alphabetical character.', 'hostname') unless $name =~ m/^[a-z]/;
            ouch(442, 'Hostname must be at least three characters long.', 'hostname') if length($name) < 3;
    
            # find with duplicates
            my $objects = $self->result_source->schema->resultset($class);
            if ($self->in_storage) {
                $objects = $objects->search({ id => { '!=' => $self->id }});
            }
            if ($objects->search({ hostname => $name })->count) {
                ouch(442, 'That Hostname is already in use.', 'hostname');
            }
        }
    });
};

around sqlt_deploy_hook => sub {
    my ($orig, $self, $sqlt_table) = @_;
    $orig->($self, $sqlt_table);
    $sqlt_table->add_index(name => 'idx_hostname', fields => ['hostname']);
};

around describe => sub {
    my ($orig, $self, %options) = @_;
    my $out = $orig->($self, %options);
    $out->{hostname} = $self->hostname;
    return $out;
};

around postable_params => sub {
    my ($orig, $self) = @_;
    my $params = $orig->($self);
    push @$params, qw(hostname);
    return $params;
};

1;

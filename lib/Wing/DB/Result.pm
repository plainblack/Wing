package Wing::DB::Result;

use Wing::Perl;
use DateTime;
use Ouch;
use base 'DBIx::Class::Core';

__PACKAGE__->load_components('UUIDColumns', 'TimeStamp', 'InflateColumn::DateTime', 'InflateColumn::Serializer', 'Core');

sub wing_apply_relationships {}

sub wing_apply_fields {
    my $class = shift;
    $class->add_columns(
        id                      => { data_type => 'char', size => 36, is_nullable => 0 },
        date_created            => { data_type => 'datetime', set_on_create => 1 },
        date_updated            => { data_type => 'datetime', set_on_create => 1, set_on_update => 1 },
    );
    $class->set_primary_key('id');
    $class->uuid_columns('id');
}

sub wing_finalize_class {
    my ($class, %options) = @_;
    $class->table($options{table_name});
    $class->uuid_class('::Data::GUID');
    $class->wing_apply_fields;
    $class->wing_apply_relationships;
}

# override default DBIx::Class constructor to set defaults from schema
sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    foreach my $col ($self->result_source->columns) {
        my $default = $self->result_source->column_info($col)->{default_value};
        $self->$col($default) if (defined $default && !defined $self->$col());
    }
    return $self;
}

sub wing_object_class {
    my $self = shift;
    my $class = ref $self || $self;    
    $class =~ s/^.*:(\w+)$/$1/;
    return $class;
}

sub wing_object_name {
    my $self = shift;
    return $self->wing_object_class;
}

sub wing_object_type {
    my $self = shift;
    return lc($self->wing_object_class);
}

sub wing_object_api_uri {
    my $self = shift;
    return '/api/'.$self->wing_object_type.'/'.$self->id;
}

sub describe {
    my ($self, %options) = @_;
    my $out = {
        id          => $self->id,
        object_type => $self->wing_object_type,
        object_name => $self->wing_object_name,
        date_updated=> Wing->to_RFC3339($self->date_updated),
        date_created=> Wing->to_RFC3339($self->date_created),
    };
    if ($options{include_options}) {
        $out->{_options} = $self->field_options;
    }
    if ($options{include_relationships}) {
        $out->{_relationships}{self} = $self->wing_object_api_uri;
    }
    return $out;
}

sub field_options {
    return {};
}

sub touch {
    my $self = shift;
    $self->update({date_updated => DateTime->now});
}

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;
    $sqlt_table->add_index(name => 'idx_date_created', fields => ['date_created']);
    $sqlt_table->add_index(name => 'idx_date_updated', fields => ['date_updated']);
}

sub postable_params {
    return [];
}

sub required_params {
    return [];
}

sub admin_postable_params {
    return [];
}

sub can_use {
    my ($self, $user) = @_;
    return 1 if defined $user && $user->is_admin;
    ouch(450, 'Insufficient privileges.');
}

sub verify_creation_params {
    my ($self, $params, $current_user) = @_;
    foreach my $param (@{$self->required_params}) {
        ouch(441, $param.' is required.', $param) unless $params->{$param} || $self->$param;
    }
}

sub verify_posted_params {
    my ($self, $params, $current_user) = @_;
    my $required_params = $self->required_params;
    if (defined $current_user && $current_user->is_admin) {
        foreach my $param (@{$self->admin_postable_params}) {
            if (exists $params->{$param}) {
                if ($param ~~ $required_params && $params->{$param} eq '') {
                    ouch(441, $param.' is required.', $param) unless $params->{$param};
                }
                $self->$param($params->{$param});
            }
        }
    }
    foreach my $param (@{$self->postable_params}) {
        if (exists $params->{$param}) {
            if ($param ~~ $required_params && $params->{$param} eq '') {
                ouch(441, $param.' is required.', $param) unless $params->{$param};
            }
            $self->$param($params->{$param});
        }
    }
}

sub duplicate {
    my ($self) = @_;
    return $self->result_source->schema->resultset(ref $self)->new({});
}

1;
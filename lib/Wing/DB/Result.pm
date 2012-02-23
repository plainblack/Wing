package Wing::DB::Result;

use Wing::Perl;
use DateTime;
use Ouch;
use base 'DBIx::Class::Core';

__PACKAGE__->load_components('UUIDColumns', 'TimeStamp', 'InflateColumn::DateTime', 'InflateColumn::Serializer', 'Core');

sub table {
    my ($class, $table) = @_;
    $class->SUPER::table($table);
    $class->add_columns(
        id                      => { data_type => 'char', size => 36, is_nullable => 0 },
        date_created            => { data_type => 'datetime', set_on_create => 1 },
        date_updated            => { data_type => 'datetime', set_on_create => 1, set_on_update => 1 },
    );
    $class->set_primary_key('id');
    $class->uuid_class('::Data::GUID');
    $class->uuid_columns('id');
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

sub object_name {
    my $self = shift;
    my $name = ref $self || $self;
    $name =~ s/^.*:(\w+)$/$1/;
    return $name;
}

sub object_type {
    my $self = shift;
    my $type = lc(ref $self || $self);    
    $type =~ s/^.*:(\w+)$/$1/;
    return $type;
}

sub object_api_uri {
    my $self = shift;
    return '/api/'.$self->object_type.'/'.$self->id;
}

sub describe {
    my ($self, %options) = @_;
    my $out = {
        id          => $self->id,
        object_type => $self->object_type,
        object_name => $self->object_name,
    };
    if (eval { $self->can_use($options{current_user}) } ) {
        $out->{date_created} = Wing->to_RFC3339($self->date_created);
        $out->{date_updated} = Wing->to_RFC3339($self->date_updated);
    }
    if ($options{include_options}) {
        $out->{_options} = $self->field_options;
    }
    if ($options{include_relationships}) {
        $out->{_relationships}{self} = $self->object_api_uri;
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

package Wing::Role::Result::AnybodyControlled;

use Wing::Perl;
use Ouch;
use Moose::Role;

around table => sub {
    my ($orig, $class, $table) = @_;
    $orig->($class, $table);
    $class->add_columns(
        user_id             => { data_type => 'char', size => 36, is_nullable => 1 },
        tracer              => { data_type => 'char', size => 36, is_nullable => 0 },
        ipaddress           => { data_type => 'varchar', size => 128, is_nullable => 0 },
        useragent           => { data_type => 'varchar', size => 255, is_nullable => 0 },
    );
    my $user_class = $class;
    $user_class =~ s/^(.*::DB::Result::).*$/$1User/;
    $class->belongs_to('user', $user_class, 'user_id');
    
    # validation
    $class->meta->add_before_method_modifier( 'user_id' => sub {
        my ($self, $value) = @_;
        if (defined $value) {
            my $user = $self->result_source->schema->resultset('User')->find($value);
            ouch(440, 'User specified does not exist.', 'user_id') unless defined $user;
            $self->user($user);
        }
    });
};

around duplicate => sub {
    my ($orig, $self) = @_;
    my $dup = $orig->($self);
    $dup->user_id($self->user_id);
    $dup->tracer($self->tracer);
    $dup->ipaddress($self->ipaddress);
    $dup->useragent($self->useragent);
    return $dup;
};

around sqlt_deploy_hook => sub {
    my ($orig, $self, $sqlt_table) = @_;
    $orig->($self, $sqlt_table);
    $sqlt_table->add_index(name => 'idx_user_id', fields => ['user_id']);
    $sqlt_table->add_index(name => 'idx_tracer', fields => ['tracer']);
};

around describe => sub {
    my ($orig, $self, %options) = @_;
    my $out = $orig->($self, %options);
    $out->{user_id} = $self->user_id;
    if ($options{include_related_objects}) {
        $out->{user} = $self->user->describe if $self->user_id;
    }
    if ($options{include_relationships}) {
        $out->{_relationships}{user} = '/api/user/'.$self->user_id if $self->user_id;
    }
    return $out;
};

around can_use => sub {
    my ($orig, $self, $user) = @_;
    if ($self->user_id) {
        return 1 if $self->user->can_use($user);
    }
    return $orig->($self, $user);
};

around postable_params => sub {
    my ($orig, $self) = @_;
    my $params = $orig->($self);
    push @$params, qw(user_id tracer ipaddress useragent);
    return $params;
};

1;

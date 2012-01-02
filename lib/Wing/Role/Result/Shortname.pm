package Wing::Role::Result::Shortname;

use Wing::Perl;
use Ouch;
use Moose::Role;

around table => sub {
    my ($orig, $class, $table) = @_;
    $orig->($class, $table);
    $class->add_columns(
        shortname        => { data_type => 'varchar', size => 50, is_nullable => 0 },
    );
    $class->add_unique_constraint([qw/shortname/]);
    $class->meta->add_before_method_modifier('shortname', sub {
        my ($self, $name) = @_;
        if (scalar @_ >= 2) {
            ouch(442, 'Shortname cannot contain upper case characters.', 'shortname') if $name =~ m/[A-Z]/;
            ouch(442, 'Shortname cannot contain spaces.', 'shortname') if $name =~ m/\s/;
            ouch(442, 'Shortname cannot contain non-alpha-numeric characters.', 'shortname') if $name =~ m/\W/;
            ouch(442, 'Shortname must start with an alphabetical character.', 'shortname') unless $name =~ m/^[a-z]/;
            ouch(442, 'Shortname must be at least three characters long.', 'shortname') if length($name) < 3;
    
            # find with duplicates
            my $objects = $self->result_source->schema->resultset($class);
            if ($self->in_storage) {
                $objects = $objects->search({ id => { '!=' => $self->id }});
            }
            if ($objects->search({ shortname => $name })->count) {
                ouch(442, 'That Shortname has been taken.', 'shortname');
            }
        }
    });
};

around sqlt_deploy_hook => sub {
    my ($orig, $self, $sqlt_table) = @_;
    $orig->($self, $sqlt_table);
    $sqlt_table->add_index(name => 'idx_shortname', fields => ['shortname']);
};

around describe => sub {
    my ($orig, $self, %options) = @_;
    my $out = $orig->($self, %options);
    $out->{shortname} = $self->shortname;
    return $out;
};

around postable_params => sub {
    my ($orig, $self) = @_;
    my $params = $orig->($self);
    push @$params, qw(shortname);
    return $params;
};

around required_params => sub {
    my ($orig, $self) = @_;
    my $params = $orig->($self);
    push @$params, qw(shortname);
    return $params;
};

1;

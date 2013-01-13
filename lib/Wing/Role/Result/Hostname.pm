package Wing::Role::Result::Hostname;

use Wing::Perl;
use Ouch;
use Moose::Role;
with Wing::Role::Result::Field;

=head1 NAME

Wing::Role::Result::Hostname - Validation for a hostname field.

=head1 SYNOPSIS

 with 'Wing::Role::Result::Hostname';
 
=head1 DESCRIPTION

Adds a C<hostname> field to your object and validates it, and guarantees it to be unique in the system. Useful for allowing users to name L<Wing::Role::Result::Site>s in a multi-tenant environment.

=cut

before wing_finalize_class => sub {
    my ($class) = @_;
    $class->wing_field(
        hostname => {
            dbic        => { data_type => 'varchar', size => 255, is_nullable => 0 },
            view        => 'public',
            edit        => 'postable',
            indexed     => 1,
        }
    );
};

after wing_finalize_class => sub {
    my ($class) = @_;
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

1;

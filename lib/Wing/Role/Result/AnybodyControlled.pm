package Wing::Role::Result::AnybodyControlled;

use Wing::Perl;
use Ouch;
use Moose::Role;
with 'Wing::Role::Result::Field';
with 'Wing::Role::Result::Parent';

before wing_finalize_class => sub {
    my ($class) = @_;
    $class->wing_fields(
        tracer => {
            dbic        => { data_type => 'char', size => 36, is_nullable => 0 },
            view        => 'public',
            edit        => 'postable',
            indexed     => 1,
        },
        ipaddress => {
            dbic        => { data_type => 'varchar', size => 128, is_nullable => 0 },
            view        => 'public',
            edit        => 'postable',
            indexed     => 1,
        },
        useragent => {
            dbic        => { data_type => 'varchar', size => 255, is_nullable => 0 },
            view        => 'public',
            edit        => 'postable',
            indexed     => 1,
        },
    );
    
    my $namespace = $class;
    $namespace =~ s/^(\w+)\:.*$/$1/;
    $class->wing_parent(
        user    => {
            view        => 'public',
            edit        => 'postable',
            related_class   => $namespace.'::DB::Result::User',
        }
    );
};

around can_use => sub {
    my ($orig, $self, $user, $tracer) = @_;
    if ($self->user_id) {
        return 1 if $self->user->can_use($user);
    }
    return $orig->($self, $user);
};

1;

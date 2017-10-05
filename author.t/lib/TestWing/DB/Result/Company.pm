package TestWing::DB::Result::Company;

use Moose;
use Wing::Perl;
extends 'Wing::DB::Result';
with 'Wing::Role::Result::Field';
with 'Wing::Role::Result::Child';

__PACKAGE__->wing_fields(
    name                          => {
        dbic                => { data_type => 'varchar', size => 60, is_nullable => 0 },
        view                => 'public',
        edit                => 'unique',
    },
    web_url                     => {
        dbic                => { data_type => 'varchar', size => 255, is_nullable => 1 },
        view                => 'public',
        edit                => 'postable',
    },
    private_info        => {
        dbic                => { data_type => 'varchar', size => 255, is_nullable => 1 },
        view                => 'admin',
        edit                => 'admin',
        check_privilege     => 'extra_privilege_switch',
    },
);

__PACKAGE__->wing_child(
    employees    => {
        view            => 'public',
        related_class   => 'TestWing::DB::Result::Employee',
        related_id      => 'company_id',
    }
);

__PACKAGE__->wing_finalize_class( table_name => 'companies');

around can_edit => sub {
    my ($orig, $self, $user, $tracer) = @_;
    if ($self->is_owner) {
        return 1;
    }
    return $orig->($self, $user);
};

has is_owner => (
    is      => 'rw',
    default => 0,
);

has privilege_switch => (
    is      => 'rw',
    default => 0,
);

sub extra_privilege_switch {
    my $self = shift;
    return $self->privilege_switch;
}

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);

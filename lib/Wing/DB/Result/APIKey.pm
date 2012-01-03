package Wing::DB::Result::APIKey;

use Moose;
use Wing::Perl;
use Ouch;
extends 'Wing::DB::Result';
with 'Wing::Role::Result::Field';
with 'Wing::Role::Result::UserControlled';

__PACKAGE__->table('api_keys');
__PACKAGE__->register_fields(
    name    => {
        dbic    => { data_type => 'varchar', size => 30, is_nullable => 0 },
        view    => 'public',
        edit    => 'unique',
    },
    uri                     => {
        dbic    => { data_type => 'varchar', size => 255, is_nullable => 1 },
        view    => 'public',
        edit    => 'postable',
    },
    reason                  => {
        dbic    => { data_type => 'varchar', size => 255, is_nullable => 1 },
        view    => 'private',
        edit    => 'postable',
    },
    private_key             => {
        dbic    => { data_type => 'char', size => '36', is_nullable => 1 },
        view    => 'private',
    },
);

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);


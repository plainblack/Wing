package Wing::Role::Result::APIKey;

use Wing::Perl;
use Ouch;
use Moose::Role;
with 'Wing::Role::Result::Field';
with 'Wing::Role::Result::UserControlled';

around table => sub {
    my ($orig, $class, $table) = @_;
    $orig->($class, $table);
    $class->register_fields(
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
};

1;

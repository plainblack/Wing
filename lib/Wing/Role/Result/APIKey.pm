package Wing::Role::Result::APIKey;

use Wing::Perl;
use Ouch;
use Moose::Role;
with 'Wing::Role::Result::Field';
with 'Wing::Role::Result::UserControlled';
with 'Wing::Role::Result::Child';

before wing_finalize_class => sub {
    my ($class) = @_;
    $class->wing_fields(
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

    my $namespace = $class;
    $namespace =~ s/^(\w+)\:.*$/$1/;
    $class->wing_child(
        permissions   => {
            view                => 'private',
            related_class       => $namespace.'::DB::Result::APIKeyPermission',
            related_id          => 'api_key_id',
        }
    );

};

1;

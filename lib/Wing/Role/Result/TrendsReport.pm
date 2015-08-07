package Wing::Role::Result::TrendsReport;

use Wing::Perl;
use Ouch;
use Moose::Role;
with 'Wing::Role::Result::Field';

before wing_finalize_class => sub {
    my ($class) = @_;
    $class->wing_fields(
        name => {
            dbic 		=> { data_type => 'varchar', size => 60, is_nullable => 0 },
            view		=> 'public',
            edit		=> 'required',
        },
        fields => {
            dbic        => { data_type => 'mediumblob', is_nullable => 1, 'serializer_class' => 'JSON'},
            view        => 'public',
            edit		=> 'postable',
        },
    );
};

1;

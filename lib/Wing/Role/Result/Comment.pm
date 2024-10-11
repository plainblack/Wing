package Wing::Role::Result::Comment;

use Moose::Role;
use Wing::Perl;
use Ouch;
use Wing::Util qw/is_in/;

with 'Wing::Role::Result::Field';
with 'Wing::Role::Result::UserControlled';
with 'Wing::Role::Result::Trendy';

requires 'comment_relationship_name';

before wing_finalize_class => sub {
    my ($class) = @_;
    $class->wing_fields(
        comment => {
            dbic    => { data_type => 'mediumtext', is_nullable => 0 },
            view    => 'public',
            edit    => 'required',
        },
        like_count => {
            dbic    => { data_type => 'int', is_nullable => 0, default_value => 0 },
            view    => 'public',
        },
        likes => {
            dbic    => { data_type => 'mediumblob', is_nullable => 1, 'serializer_class' => 'JSON', 'serializer_options' => { utf8 => 1 }  },
        },
    );
};

around describe => sub {
    my ($orig, $self, %options) = @_;
    my $out = $orig->($self, %options);
    if (exists $options{current_user} && defined $options{current_user} && $self->likes) {
        if (is_in($options{current_user}->id, $self->likes || [])) {
            $out->{i_like} = 1;
        }
    }
    return $out;
};

sub comment_relationship_id {
    my $self = shift;
    my $method = $self->comment_relationship_name.'_id';
    return $self->$method(@_);
}

sub like {
    my ($self, $user_id) = @_;
    my $likes = $self->likes || [];
    return if is_in($user_id, $likes);
    push @{$likes}, $user_id;
    $self->likes($likes);
    $self->like_count(scalar @{$likes});
    $self->update;
}

sub unlike {
    my ($self, $user_id) = @_;
    my $likes = $self->likes || [];
    my $index = 0;
    $index++ until $likes->[$index] eq $user_id;
    splice(@{$likes}, $index, 1);
    $self->likes($likes);
    $self->like_count(scalar @{$likes});
    $self->update;
}

after insert => sub {
    my $self = shift;
    $self->log_trend('comments', 1, $self->id);
    $self->log_trend($self->comment_relationship_name, 1, $self->id);
};

1;

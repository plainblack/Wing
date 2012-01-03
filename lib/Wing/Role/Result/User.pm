package Wing::Role::Result::User;

use Wing::Perl;
use Wing::Session;
use Crypt::Eksblowfish::Bcrypt;
use Digest::MD5;
use Encode ();
use DateTime;
use Data::GUID;
use Ouch;
use Moose::Role;
with 'Wing::Role::Result::Field';
with 'Wing::Role::Result::DateTimeField';

around table => sub {
    my ($orig, $class, $table) = @_;
    $orig->($class, $table);
    $class->register_fields(
        username                => {
            dbic    => { data_type => 'varchar', size => 30, is_nullable => 0 },
            view    => 'private',
            edit    => 'unique',
        },
        real_name               => {
            dbic    => { data_type => 'varchar', size => 255, is_nullable => 1 },
            view    => 'private',
            edit    => 'postable',
        },
        email                   => {
            dbic    => { data_type => 'varchar', size => 255, is_nullable => 1 },
            view    => 'private',
            edit    => 'unique',
        },
        use_as_display_name     => {
            dbic    => { data_type => 'varchar', size => 10, is_nullable => 1, default_value => 'username' },
            view    => 'private',
            edit    => 'postable',
            options => [qw(username real_name email)],
            _options=> { username => 'Username', real_name => 'Real Name', email => 'Email Address' },
        },
        password                => {
            dbic    => { data_type => 'char', size => 50 },
        },
        password_type           => {
            dbic    => { data_type => 'varchar', size => 10, is_nullable => 0, default_value => 'bcrypt' },
        },
        admin                   => {
            dbic    => { data_type => 'tinyint', default_value => 0 },
            view    => 'private',
            edit    => 'admin',
        },
    );
    $class->register_datetime_field(
        last_login  => {
            view            => 'private',
            set_on_create   => 1,
        }
    );
};

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;
    $sqlt_table->add_index(name => 'idx_search', fields => ['real_name','username','email']);
}

around describe => sub {
    my ($orig, $self, %options) = @_;
    my $out = $orig->($self, %options);
    $out->{display_name} = $self->display_name;
    return $out;
};

sub start_session {
    my ($self, $options) = @_;
    $self->last_login(DateTime->now);
    $self->update;
    return Wing::Session->new(db => $self->result_source->schema, cache => MobRaterManager->cache)->start($self, $options);
}

sub display_name {
    my $self = shift;
    given ($self->use_as_display_name) {
        when ('username') { return $self->username }
        when ('email') { return $self->email }
        when ('real_name') { return $self->real_name }
    }
}

sub is_admin {
    my $self = shift;
    return $self->admin;
}

sub is_password_valid {
    my ($self, $password) = @_;
    my $encrypted_password;
    given ($self->password_type) {
        when ('md5') { $encrypted_password = Digest::MD5::md5_base64(Encode::encode_utf8($password)) }
        default { $encrypted_password = $self->encrypt($password) }
    }
    if (defined $password && $password ne '' && $self->password eq $encrypted_password) {
        if ($self->password_type eq 'md5') { # while we have the password in the clear, let's upgrade the encryption
            $self->password_type('bcrypt');
            $self->password($self->encrypt($password));
            $self->update;
        }
        return 1;
    }
    else {
        return 0;
    }
}

sub encrypt_and_set_password {
    my ($self, $password) = @_;
    unless (length($password) >= 6) {
        ouch 443, "The password specified is too short. Must be at least 6 characters.", 'password';
    }
    $self->password($self->encrypt($password));
    $self->password_type('bcrypt');
    return $self;
}

sub encrypt {
    my ($self, $password) = @_;
    return Crypt::Eksblowfish::Bcrypt::en_base64(
        Crypt::Eksblowfish::Bcrypt::bcrypt_hash({
            key_nul     => 1,
            cost        => 8,
            salt        => 'THEGAMECRAFTERSA',
        }, Encode::encode_utf8($password))
    );
}

around can_use => sub {
    my ($orig, $self, $user) = @_;
    return 1 if defined $user && ($user->id eq $self->id || $user->is_admin);
    return $orig->($self, $user);
};

before verify_posted_params => sub {
    my ($self, $params, $current_user) = @_;
    if (defined $current_user && $current_user->is_admin && $params->{md5_password} && $params->{password}) {
        $self->password($params->{password});
        $self->password_type('md5');
    }
    elsif ($params->{password}) {
        $self->encrypt_and_set_password($params->{password});
    }
};

has rpc_count => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        my $self = shift;
        my $key = 'rpc_count_'.DateTime->now->minute.$self->id;
        my $value = MobRaterManager->cache->get($key) + 1;
        MobRaterManager->cache->set($key, $value, { expires_in => 60 });
    }
);

has current_session => (
    is                  => 'rw',
    predicate           => 'has_current_session',
);

1;

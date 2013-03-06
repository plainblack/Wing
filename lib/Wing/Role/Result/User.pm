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
use String::Random;
with 'Wing::Role::Result::Field';
with 'Wing::Role::Result::DateTimeField';
with 'Wing::Role::Result::PrivilegeField';
with 'Wing::Role::Result::Child';


=head1 NAME

Wing::Role::Result::User - The basis of Wing users.

=head1 SYNOPSIS

 with 'Wing::Role::Result::User';
 
=head1 DESCRIPTION

This is a foundational role which is required to create user objects. Users allow access and permissions to be defined in your applications.

=head1 REQUIREMENTS

All Wing Apps need to have a class called AppName::DB::Result::User that uses this role as a starting point.

=head1 ADDS

=head2 Fields

=over

=item username

The name this user will type to authenticate themselves.

=item real_name

Their name in meatspace.

=item email

Their contact email address.

=item use_as_display_name

The field the user wishes to be used to display their name to other users. Must be one of C<username>, C<email>, or C<real_name>.

=item password

The encrypted version of the user's text-based password.

=item password_type

The method of encryption used on the user's password.

=item admin

A boolean indicating whether or not the user should be treated as an admin. See also L<Wing::Role::Result::PrivilegeField>.

=item developer

A boolean indicating whether or not the user should be treated as a software developer for the Restful API. See also L<Wing::Role::Result::PrivilegeField>.

=item last_login

A datetime indicating the time last time this user authenticated to the system. See also L<Wing::Role::Result::DateTimeField>.

=back

=head2 Children

=over

=item api_keys

A relationship to a L<Wing::Role::Result::APIKeyPermmission> enabled object.

=item api_key_permissions

=back

=cut

before wing_finalize_class => sub {
    my ($class) = @_;
    $class->wing_fields(
        username                => {
            dbic    => { data_type => 'varchar', size => 30, is_nullable => 0 },
            view    => 'private',
            edit    => 'unique',
        },
        real_name               => {
            dbic    => { data_type => 'varchar', size => 255, is_nullable => 0, default_value => '' },
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
        password_salt           => {
            dbic    => { data_type => 'char', size => 16, is_nullable => 0, default_value => 'abcdefghijklmnop' }, # the default is here in case someone creates a user without a password, so we don't error all over the place
        },
        password_type           => {
            dbic    => { data_type => 'varchar', size => 10, is_nullable => 0, default_value => 'bcrypt' },
        },
        admin                   => {
            dbic    => { data_type => 'tinyint', default_value => 0 },
            options => [0,1],
            _options=> { 0 => 'No', 1 => 'Yes' },
            view    => 'private',
            edit    => 'admin',
        },
    );
    $class->wing_privilege_fields(
        developer               => {edit => 'postable'},
    );
    $class->wing_datetime_field(
        last_login  => {
            view            => 'private',
            set_on_create   => 1,
        }
    );
    my $namespace = $class;
    $namespace =~ s/^(\w+)\:.*$/$1/;
    $class->wing_children(
        api_keys  => {
            view                => 'private',
            related_class       => $namespace.'::DB::Result::APIKey',
            related_id          => 'user_id',
        },
        api_key_permissions  => {
            view                => 'private',
            related_class       => $namespace.'::DB::Result::APIKeyPermission',
            related_id          => 'user_id',
        },
    );
};

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;
    $sqlt_table->add_index(name => 'idx_search', fields => ['real_name','username','email']);
}

before delete => sub {
    my $self = shift;

};

around describe => sub {
    my ($orig, $self, %options) = @_;
    my $out = $orig->($self, %options);
    $out->{display_name} = $self->display_name;
    if ($options{include_private}) {
        $out->{is_admin} = $self->is_admin;
    }
    return $out;
};

=head2 Methods

=over

=item start_session (options)

Starts a new session for this user. See C<start> in L<Wing::Session> for details.

=item display_name

Returns the user's preferred display name based upon the L<use_as_display_name> field. 

=item is_password_valid ( password )

Validates that the password supplied matches the user's defined password and returns a 1 or 0 to indicate success or failure.

=item encrypt_and_set_password ( password )

Given a string of text, encrypts the password and sets it in the user's account. Ouches 443 if not able to set.

=item encrypt ( password )

A utility function to encrypt a password. Useful for verifying passwords and setting passwords.

=item rpc_count

Returns an integer indicating how many web service requests this user has made in the past 60 seconds.

=item current_session

Returns a reference to the current L<Wing::Session> object if any.

=item send_templated_email ( template, params, options )

Sends a templated email to this user. See C<send_templated_email> in L<Wing> for details.

=back

=cut



sub start_session {
    my ($self, $options) = @_;
    $self->last_login(DateTime->now);
    $self->update;
    return Wing::Session->new(db => $self->result_source->schema)->start($self, $options);
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

sub verify_is_admin {
    my $self = shift;
    unless ($self->is_admin) {
        ouch 450, 'You must be an admin to do that.';
    }
    return $self;
}

sub is_password_valid {
    my ($self, $password) = @_;
    my $encrypted_password;
    given ($self->password_type) {
        when ('md5') { $encrypted_password = Digest::MD5::md5_base64(Encode::encode_utf8($password)) }
        default { $encrypted_password = $self->encrypt($password, $self->password_salt) }
    }
    if (defined $password && $password ne '' && $self->password eq $encrypted_password) {
        if (defined $self->password_type && $self->password_type eq 'md5') { # while we have the password in the clear, let's upgrade the encryption
            $self->encrypt_and_set_password($password)->update;
        }
        return 1;
    }
    else {
        return 0;
    }
}

sub encrypt_and_set_password {
    my ($self, $password) = @_;
    my $salt = String::Random->new->randpattern('ssssssssssssssss');
    $self->password($self->encrypt($password, $salt));
    $self->password_salt($salt);
    $self->password_type('bcrypt');
    return $self;
}

sub encrypt {
    my ($self, $password, $salt) = @_;
    return Crypt::Eksblowfish::Bcrypt::en_base64(
        Crypt::Eksblowfish::Bcrypt::bcrypt_hash({
            key_nul     => 1,
            cost        => 8,
            salt        => $salt,
        }, Encode::encode_utf8($password))
    );
}

around can_edit => sub {
    my ($orig, $self, $user) = @_;
    return 1 if defined $user && $user->id eq $self->id;
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
        my $value = (Wing->cache->get($key) || 0) + 1;
        Wing->cache->set($key, $value, { expires_in => 60 });
    }
);

has current_session => (
    is                  => 'rw',
    predicate           => 'has_current_session',
);

sub send_templated_email {
    my ($self, $template, $params, $options) = @_;
    unless ($self->email) {
        ouch 441, "No email address associated with this user.", 'email';
    }
    unless ($self->email =~ '\@') {
        ouch 442, "Illegal email address for this user.", 'email';
    }
    $params->{me} = $self->describe(include_private => 1);
    Wing->send_templated_email($template, $params, $options);
    return $self;
}


1;

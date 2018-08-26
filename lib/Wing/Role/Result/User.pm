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
use String::Random qw(random_string);
use Crypt::JWT qw(encode_jwt);
with 'Wing::Role::Result::Field';
with 'Wing::Role::Result::DateTimeField';
with 'Wing::Role::Result::PrivilegeField';
with 'Wing::Role::Result::Child';
use Wing::ContentFilter;
use Wing::Firebase;

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

=item facebook_uid

String. The unique id of a user's Facebook account.

=item facebook_token

String. The token Facebook gives us to allow us to take actions for a user on Facebook.

=item email

Their contact email address.

=item no_email

Boolean. This person wants no email from us what-so-ever.

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

=item last_ip

The IP address when the user last logged in or created their account.

=back

=head2 Children

=over

=item apikeys

A relationship to a L<Wing::Role::Result::APIKeyPermmission> enabled object.

=item apikeypermissions

=back

=cut

sub fix_html {
    my $text = shift;
    Wing::ContentFilter::neutralize_html(\$text);
    return $text;
}

before wing_finalize_class => sub {
    my ($class) = @_;

    $class->wing_fields(
        username                => {
            dbic    => { data_type => 'varchar', size => 30, is_nullable => 0 },
            view    => 'private',
            edit    => 'unique',
            filter  => sub { Wing::ContentFilter::neutralize_html(\$_[0], {entities=>1},); return $_[0]; },
        },
        real_name               => {
            dbic    => { data_type => 'varchar', size => 255, is_nullable => 1, default_value => '' },
            view    => 'private',
            edit    => 'postable',
            filter  => sub { Wing::ContentFilter::neutralize_html(\$_[0], {entities=>1},); return $_[0]; },
        },
        facebook_uid            => {
            dbic                => { data_type => 'bigint', is_nullable => 1 },
            view                => 'private',
            edit                => 'admin',
        },
        facebook_token          => {
            dbic                => { data_type => 'varchar', size => 100, is_nullable => 1 },
            view                => 'private',
            edit                => 'admin',
        },
        email                   => {
            dbic    => { data_type => 'varchar', size => 255, is_nullable => 1 },
            view    => 'private',
            edit    => 'unique',
            filter  => sub { Wing::ContentFilter::neutralize_html(\$_[0]); return $_[0]; },
        },
        last_ip                   => {
            dbic    => { data_type => 'varchar', size => 20, is_nullable => 1 },
            view    => 'private',
        },
        no_email     => {
            dbic                => { data_type => 'tinyint', default_value => 0 },
            options             => [0,1],
            _options            => { 0 => 'Send Email', 1 => 'No Email Ever' },
            view                => 'private',
            edit                => 'postable',
        },
        permanently_deactivated  => {
            dbic                => { data_type => 'tinyint', default_value => 0 },
            options             => [0,1],
            _options            => { 0 => 'Active', 1 => 'Permanently deactivated' },
            view                => 'private',
            edit                => 'admin',
        },
        use_as_display_name     => {
            dbic    => { data_type => 'varchar', size => 10, is_nullable => 1, default_value => 'username' },
            view    => 'private',
            edit    => 'postable',
            options => [qw(username real_name email)],
            _options=> { username => 'Username', real_name => 'Real Name', email => 'Email Address' },
        },
        password                => {
            dbic    => { data_type => 'char', size => 50, is_nullable => 1 },
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
        apikeys  => {
            view                => 'private',
            related_class       => $namespace.'::DB::Result::APIKey',
            related_id          => 'user_id',
        },
        apikeypermissions  => {
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

around describe => sub {
    my ($orig, $self, %options) = @_;
    my $out = $orig->($self, %options);
    $out->{display_name} = $self->display_name;
    $out->{view_uri} = $self->view_uri;
    if ($options{include_private}) {
        $out->{edit_uri} = $self->edit_uri;
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

=item generate_password_reset_code ( )

Generates a password reset code that is valid for 24 hours and returns it.

=item firebase_jwt ( [ claims ] )

Returns a Firebase JWT auth token according to the Firebase Client 4.x specification.

=over

=item claims

Optional. A hash reference of claims to add to the firebase auth token. Example:

 { moderator : 1 }

=back


=item  firebase_status ( payload )

Displays a status message in the user's browser.

=over

=item payload

Can be either a scalar or a hash reference. If it's a scalar, then the scalar will be displayed as an info message to the user (the most common case). If it's a hash reference, then it should take the form of:

 {
    message => 'some message',
    type    => 'info'
 }

Where C<type> can be one of C<info>, C<error>, C<warn> C<success>.

=item type

If not specified in a hash reference payload, you can set the type as an optional second parameter. Defaults to C<info>. Must be one of C<info>, C<error>, C<warn> C<success>.

=item has_secondary_auth_token ()

A 2 factor authentication token has been verified recently.

=item email_secondary_auth_verification ([redirect])

Send an email to verify a user is who they say they are so we can set a 2 factor auth token.

=over

=item A partial URL within the site to redirect to after authentication.

=back

=item verify_secondary_auth (token)

Check a secondary auth token to see if it is valid, and if it is, generate a secondary auth token.

=over

=item The token generated by email_secondary_auth_verification

=back

=back

=cut

sub firebase_jwt {
    my $self = shift;
    my $claims = shift;
    my $firebase_config = Wing->config->get('firebase');
    my $now = time();
    my $payload = {
        iss     => $firebase_config->{service_email},
        sub     => $firebase_config->{service_email},
        aud     => "https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit",
        iat     => $now,
        exp     => $now+(60*60),  # Maximum expiration time is one hour
        uid     => $self->id,
    };
    if (defined $claims && ref $claims eq 'HASH') {
        $payload->{claims} = $claims;
    }
    return encode_jwt(
        payload     => $payload,
        alg         => 'RS256',
        key         => \$firebase_config->{admin_key},
    );
}

sub firebase_status {
    my ($self, $payload, $type) = @_;
    unless (ref $payload eq 'HASH') {
        $payload = {
            message => $payload,
            type    => $type || 'info'
        };
    }
    Wing::Firebase->new->object_status($self,  $payload);
    my $log_type = $payload->{type};
    $log_type = 'info' if ($log_type eq 'success');
    Wing->log->$log_type('Firebase status to '.$self->username.': '.$payload->{message});
}



=head2 post_message_to_chat ( message, [ options ] )

Posts a message to the chat system.

=over

=item room_id

The unique id of a room to post to. Defaults to the id of the general chat room.

=item message_type

Must be C<activity> or C<default>. Defaults to C<default>. Activity messages are the equivalent of typing C</me message> in the chat.

=back

=cut

sub post_message_to_chat {
    my ($self, $message, $options) = @_;
    my $room_id = $options->{room_id} || 'general-chat'; # defaults to general chat
    my $firebase_config = Wing->config->get('firebase');
    return Wing::Firebase->new->post('chat/messages/'.$room_id, {
        user_id     => $self->id,
        name        => $self->display_name,
        timestamp   => {".sv"   => "timestamp"},
        text        => $message,
        type        => $options->{message_type} || 'message',
        '.priority' => {".sv"   => "timestamp"},
    });
}

=head2 is_chat_moderator

Returns a boolean if the user has chat moderator privileges.

=cut

sub is_chat_moderator {
    my $self = shift;
    return $self->is_chat_staff;
}

=head2 is_chat_staff

Returns a boolean if the user has chat staff privileges.

=cut

sub is_chat_staff {
    my $self = shift;
    return $self->is_admin ? 1 : 0;
}

sub has_secondary_auth_token {
    my $self = shift;
    return Wing->cache->get('2factor-verified-'.$self->id);
}

sub email_secondary_auth_verification {
    my ($self, $redirect) = @_;
    my $verify = random_string('ssssssss');
    Wing->cache->set('2factor-verify-'.$self->id, $verify, 60 * 10);
    eval {
        $self->send_templated_email('secondary_auth', { token => $verify, redirect => $redirect });
    };
    if ($@) {
        ouch 428, 'We need to send you an email to verify you are who you say you are before displaying the page you requested, but received this error when doing so: '.bleep($@).' Please contact customer service to solve this problem.';
    }
}

sub verify_secondary_auth {
    my ($self, $token) = @_;
    if (defined $token && $token ne "" && $token eq Wing->cache->get('2factor-verify-'.$self->id)) {
        return Wing->cache->set('2factor-verified-'.$self->id, 1, 60 * 60 * 24);
    }
    return 0;
}

sub start_session {
    my ($self, $options) = @_;
    ouch 442, 'User is permanently deactivated' if $self->permanently_deactivated;
    $self->last_login(DateTime->now);
    $self->last_ip($options->{ip_address});
    $self->update;
    return Wing::Session->new(db => $self->result_source->schema)->start($self, $options);
}

sub deactivate {
    my $self = shift;
    $self->permanently_deactivated(1);
    $self->password('deactivated');
    $self->update;
}

sub display_name {
    my $self = shift;
    if ($self->use_as_display_name eq 'username') {
        return $self->username;
    }
    elsif ($self->use_as_display_name eq 'email') {
        return $self->email;
    }
    elsif ($self->use_as_display_name eq 'real_name') {
        return $self->real_name;
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
    ouch 442, 'User is permanently deactivated' if $self->permanently_deactivated;
    my $encrypted_password;
    if ($self->password_type eq 'md5') {
        $encrypted_password = Digest::MD5::md5_base64(Encode::encode_utf8($password));
    }
    else {
        $encrypted_password = $self->encrypt($password, $self->password_salt);
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
    if ($self->no_email or $self->permanently_deactivated) {
        ouch 442, 'This user does not want any email.';
    }
    $params->{me} = $self->describe(include_private => 1);
    Wing->send_templated_email($template, $params, $options);
    return $self;
}

sub generate_password_reset_code {
    my $self = shift;
    ouch 442, 'User is permanently deactivated' if $self->permanently_deactivated;
    my $code = random_string('ssssssssssssssssssssssssssssssssssss');
    Wing->cache->set('password_reset'.$code, $self->id, 60 * 60 * 24);
    return $code;
}

before delete => sub {
    my $self = shift;
    $self->apikeypermissions->delete_all;
    $self->apikeys->delete_all;
};

sub view_uri {
    my $self = shift;
    return '/account/profile/'.$self->id;
}

sub edit_uri {
    my $self = shift;
    return '/account';
}

sub determine_avatar_uri {
    my $self = shift;
    if ($self->facebook_uid) {
        return '//graph.facebook.com/'.$self->facebook_uid.'/picture';
    }
    else {
        return '//www.gravatar.com/avatar/'.md5_hex($self->email);
    }
}

1;

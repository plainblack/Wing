package Wing::Rest;

use strict;
use warnings;
use Ouch;
use Dancer ':syntax';
use Dancer::Plugin;

set serializer => 'JSON';

require Wing::Dancer;

register get_session => sub {
    my (%options) = @_;
    my $session_id = $options{session_id} || params->{session_id};
    my $cookie = cookies->{session_id};
    if (!defined $session_id && defined $cookie) {
        $session_id = $cookie->value;
    }
    unless (defined $session_id) {
        ouch 441, 'session_id is required', 'session_id';
    }
    return $session_id if (ref $session_id eq 'Wing::Session');
    my $session = Wing::Session->new( id => $session_id, db => site_db() );
    if ($session->user_id) {
        $session->check_permissions($options{permissions});
        $session->extend;
        return $session;
    }
    else {
        ouch 451, 'Session expired.', $session_id;
    }
};

register get_user_by_session_id => sub {
    my $session = get_session(@_);
    return $session if (ref $session =~ m/DB::Result::User$/);
    my $user = $session->user;
    if (defined $user) {
        my $max = Wing->config->get('rpc_limit') || 30;
        if ($user->rpc_count > $max) {
            ouch 452, 'Slow down! You are only allowed to make ('.$max.') requests per minute to the server.', $max;
        }
        return $user;
    }
    return undef;
};

register describe => sub {
    my ($object, $current_user) = @_;
    $current_user ||= eval { get_user_by_session_id() };
    return $object->describe(
        include_private         => (eval { $object->can_use($current_user) }) ? 1 : 0,
        include_admin           => (eval { defined $current_user && $current_user->is_admin }) ? 1 : 0,
        include_relationships   => params->{_include_relationships},
        include_options         => params->{_include_options},
        include_related_objects => params->{_include_related_objects},
        current_user            => $current_user,
        tracer                  => get_tracer(),
    );
};

register generate_delete => sub {
    my ($wing_object_type, %options) = @_;
    my $object_url = lc($wing_object_type);
    del '/api/'.$object_url.'/:id'  => sub {
        my $object = fetch_object($wing_object_type);
        $object->can_use(get_user_by_session_id(permissions => $options{permissions}));
        $object->delete;
        return { success => 1 };
    };
};

register generate_update => sub {
    my ($wing_object_type, %options) = @_;
    my $object_url = lc($wing_object_type);
    put '/api/'.$object_url.'/:id'  => sub {
        my $current_user = get_user_by_session_id(permissions => $options{permissions});
        my $object = fetch_object($wing_object_type);
        $object->can_use($current_user);
        $object->verify_posted_params(expanded_params(), $current_user);
        if (exists $options{extra_processing}) {
            $options{extra_processing}->($object, $current_user);
        }
        $object->update;
        return describe($object, $current_user);
    };
};

register generate_create => sub {
    my ($wing_object_type, %options) = @_;
    my $object_url = lc($wing_object_type);
    post '/api/'.$object_url => sub {
        my $object = site_db()->resultset($wing_object_type)->new({});
        my $params = expanded_params();
        my $current_user = get_user_by_session_id(permissions => $options{permissions});
        $object->verify_creation_params($params, $current_user);
        $object->verify_posted_params($params, $current_user);
        if (defined $options{extra_processing}) {
            $options{extra_processing}->($object, $current_user);
        }
        $object->insert;
        return describe($object, $current_user);
    };
};

register generate_read => sub {
    my ($wing_object_type, %options) = @_;
    my $object_url = lc($wing_object_type);
    get '/api/'.$object_url.'/:id' => sub {
        my $current_user = eval{ get_user_by_session_id(permissions => $options{permissions}) };
        return describe(fetch_object($wing_object_type), $current_user);
    };
};

register generate_options => sub {
    my ($wing_object_type) = @_;
    my $object_url = lc($wing_object_type);
    get '/api/'.$object_url.'/_options' => sub {
        return site_db()->resultset($wing_object_type)->new({})->field_options(
            include_relationships   => params->{_include_relationships},
            include_options         => params->{_include_options},
            include_related_objects => params->{_include_related_objects},
            current_user            => eval { get_user_by_session_id() },
        );
    };
};

register generate_crud => sub {
    my ($wing_object_type) = @_;
    generate_options($wing_object_type);
    generate_read($wing_object_type);
    generate_update($wing_object_type);
    generate_delete($wing_object_type);
    generate_create($wing_object_type);
};

hook after => sub {
    my $response = shift;
    $response->content(to_json({ result => from_json($response->content) }));
    debug $response->content;
    return $response;
};

hook before_error_init => sub {
    my $error = shift;
    set show_errors => 1;
    if (ref $error->exception eq 'Ouch') {
        $error->{message} = {
            error   => $error->exception->hashref,
        };
        $error->{code} = $error->exception->code =~ m/^\d{3}$/ ? $error->exception->code : 500;
    }
    else {
        $error->{message} = {
            error   => {
                code    => 500,
                message => $error->message,
                data    => undef,
            }
        };
        $error->{code} = 500;
    }
    delete $error->{exception};
};

hook(
    after_serializer => sub {
        my $response = shift;
        $response->{encoded} = 1;
    }
);

register_plugin;

1;


=head1 NAME

Wing::Rest - Dancer plugin to generate Rest from Wing classes.

=head1 SYNOPSIS

 package Wing::Rest::User;

 use Wing::Perl;
 use Dancer;
 use Wing::Rest;
 
 generate_crud('User');
 
 1;
 
=head1 DESCRIPTION

This L<Dancer> plugin generates restful web services from a Wing class definition. It provides a lot of nifty code-generation tools to auto-generate the web services, and also to write your own custom web services.

=head1 SUBROUTINES

=head2 get_session( options )

Unless for some reason you're only mucking around with the session and not the user, you should use C<get_user_by_session_id> instead. Will L<Ouch> a 451 if it can't find a session or the session has expired.

=over

=item options

A hash of options.

=over

=item session_id

You can pass in a session id and it will fetch the session if it exists. You can also pass in a session object here and it will simply return it back to you. If you don't pass in a session id, then it will try to find the session from a form parameter of session_id, and finally by looking for a session_id cookie.

=item permissions

If specified, it will check to see that the API Key using this session has this permission. If it doesn't, then we throw an exception instead of returning the session.

=back

=back

=head2 get_user_by_session_id ( options )

Does the same thing as C<get_session> except that it returns the User object associated with the session.  See C<get_session> for more information.
 
=head2 describe ( object, current_user )

Returns the description of the object by calling it's C<describe> method. However, it also gracefully handles all the extra modifiers such as _include_relationships and displaying private information if the user owns the object.

=over

=item object

The object you wish to describe.

=item current_user

Optional. If specified we won't bother trying to figure out who the current user is. 

=back

=head2 generate_create ( object_type, options )

Generates a web service method accessible via POST that allows you to create an object of this type.

 generate_create('User'); # POST /api/user
 
=head2 generate_read ( object_type, options )

Generates a web service method accessible via GET that allows you to fetch data about this object.

 generate_read("User"); # GET /api/user/xxx
 
=head2 generate_update ( object_type, options )

Generates a web service method accessible via PUT that allows you to update an existing object.

 generate_update('User'); # PUT /api/user/xxx
 
=head2 generate_delete ( object_type, options )

Generates a web service method accessible via DELETE that allows you to delete an existing object.

 generate_delete('User'); # DELETE /api/user/xxx

=head2 generate_options ( object_type )

Generates a web service that returns a web service of enumerated types for fields in the objects.

 generate_options('User'); # GET /api/user/_options

=head2 generate_crud ( object_type )

Does C<generate_create>, C<generate_read>, C<generate_update>, C<generate_delete>, and C<generate_options> in a single call. 

 generate_crud('User');

=head1 SEE ALSO

The subroutines from L<Wing::Dancer> are also imported into here. You should also look at L<Wing::RestUsage> for the output that will be generated by these methods. 

package Wing::Rest;

use strict;
use warnings;
use Ouch;
use Dancer ':syntax';
use Dancer::Plugin;
no warnings 'experimental::smartmatch';
use Wing::Util qw(trigram_match_against);


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
        ouch 401, 'You must log in to do that.', $session_id;
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

register generate_delete => sub {
    my ($wing_object_type, %options) = @_;
    my $object_url = lc($wing_object_type);
    del '/api/'.$object_url.'/:id'  => sub {
        my $db_class_name = %options && exists $options{db_class_name} ? $options{db_class_name} : $wing_object_type; # creates alias for migrating from old APIs to new
        my $object = fetch_object($db_class_name);
        my $current_user = eval { get_user_by_session_id(permissions => $options{permissions}); };
        $object->can_delete($current_user, get_tracer());
        if (exists $options{extra_processing}) {
            $options{extra_processing}->($object, $current_user);
        }
        $object->delete;
        return $object->describe_delete;
    };
};

register generate_update => sub {
    my ($wing_object_type, %options) = @_;
    my $object_url = lc($wing_object_type);
    put '/api/'.$object_url.'/:id'  => sub {
        my $current_user = eval { get_user_by_session_id(permissions => $options{permissions}); };
        my $db_class_name = %options && exists $options{db_class_name} ? $options{db_class_name} : $wing_object_type; # creates alias for migrating from old APIs to new
        my $object = fetch_object($db_class_name);
        $object->verify_posted_params(expanded_params($current_user), $current_user, get_tracer());
        if (exists $options{extra_processing}) {
            $options{extra_processing}->($object, $current_user);
        }
        $object->update;
        return describe($object, current_user => $current_user);
    };
};

register generate_create => sub {
    my ($wing_object_type, %options) = @_;
    my $object_url = lc($wing_object_type);
    post '/api/'.$object_url => sub {
my $name = param('name');
Wing->log->debug($object_url. ' starting '.$name);
        my $db_class_name = %options && exists $options{db_class_name} ? $options{db_class_name} : $wing_object_type; # creates alias for migrating from old APIs to new
Wing->log->debug($object_url. ' a '.$name);
        my $object = site_db()->resultset($db_class_name)->new({});
Wing->log->debug($object_url. ' b '.$name);
        my $current_user = eval { get_user_by_session_id(permissions => $options{permissions}); };
Wing->log->debug($object_url. ' c '.$name);
        my $params = expanded_params($current_user);
Wing->log->debug($object_url. ' d '.$name);
        if ($db_class_name ne $wing_object_type) { # provides an identity for migrating old APIs in case that is needed
Wing->log->debug($object_url. ' e '.$name);
            $params->{identity} = $wing_object_type;  
        }
Wing->log->debug($object_url. ' f '.$name);
use Data::Dumper;
Wing->log->debug($name.' '.Dumper($params));
        $object->verify_creation_params($params, $current_user);
if ($object->can('game_id')) {
Wing->log->debug($name.' '.Dumper($params));
Wing->log->debug($object_url. ' game_id '.$object->game_id.'  '.$name);
  if ($name eq 'InventionDeck' && !$object->game_id) {
    $object->game_id($params->{game_id});
 }
Wing->log->debug($object_url. ' game_id '.$object->game_id.'  '.$name);
}
Wing->log->debug($object_url. ' g '.$name);
        $object->verify_posted_params($params, $current_user, get_tracer());
Wing->log->debug($object_url. ' h '.$name);
        if (defined $options{extra_processing}) {
Wing->log->debug($object_url. ' i '.$name);
            $options{extra_processing}->($object, $current_user);
        }
Wing->log->debug($object_url. ' j '.$name);
        $object->insert;
Wing->log->debug($object_url. ' ending '.$name);
        return describe($object, current_user => $current_user);
    };
};

register generate_read => sub {
    my ($wing_object_type, %options) = @_;
    my $object_url = lc($wing_object_type);
    get '/api/'.$object_url.'/:id' => sub {
        my $current_user = eval{ get_user_by_session_id(permissions => $options{permissions}) };
        my $db_class_name = %options && exists $options{db_class_name} ? $options{db_class_name} : $wing_object_type; # creates alias for migrating from old APIs to new
        my $object = fetch_object($db_class_name);
        ##No object level permission checking here.  Wing objects are public, and only fields
        ##have permissions for reading.
        return describe($object, current_user => $current_user);
    };
};

register generate_options => sub {
    my ($wing_object_type, %options) = @_;
    my $object_url = lc($wing_object_type);
    get '/api/'.$object_url.'/_options' => sub {
        my $db_class_name = %options && exists $options{db_class_name} ? $options{db_class_name} : $wing_object_type; # creates alias for migrating from old APIs to new
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

register generate_relationship => sub {
    my ($wing_object_type, $relationship_name, %options) = @_;
    my $object_url = lc($wing_object_type);
    get '/api/'.$object_url.'/:id/'.$relationship_name => sub {
        my $current_user = eval{get_user_by_session_id(permissions => $options{permissions})};
        my $db_class_name = %options && exists $options{db_class_name} ? $options{db_class_name} : $wing_object_type; # creates alias for migrating from old APIs to new
        my $object = fetch_object($db_class_name);
        my $data = $object->$relationship_name();
        if (exists $options{queryable} || exists $options{fulltextquery} || exists $options{trigramquery}) {
            my @query;
            my $prefetch = param('_include_related_objects');
            if (defined $prefetch) {
                if (ref $prefetch ne 'ARRAY' && $prefetch !~ m/^\d$/) {
                    $prefetch = [$prefetch];
                }
            }
            if (ref $prefetch ne 'ARRAY') {
                $prefetch = [];
            }
            my $query = param('query');
            if (defined $query && $query ne '') {
                foreach my $name (@{$options{queryable}}) {
                    if ($name =~ m/(\w+)\.\w+/) { # skip a joined query if there is no prefetch on that query, needed when you have queriable params in a joined table like 'user.real_name'.
                        next unless $1 ~~ $prefetch;
                    }
                    my $key = $name =~ m/\./ ? $name : 'me.'.$name;
                    push @query, $key => { like => '%'.$query.'%' };
                }
                if (exists $options{fulltextquery} && scalar @{$options{fulltextquery}}) {
                    my @keys = ();
                    foreach my $name (@{$options{fulltextquery}}) {
                        if ($name =~ m/(\w+)\.\w+/) { # skip a joined query if there is no prefetch on that query, needed when you have queriable params in a joined table like 'user.real_name'.
                            next unless $1 ~~ $prefetch;
                        }
                        my $key = $name =~ m/\./ ? $name : 'me.'.$name;
		                push @keys, $key;
                    }
                    push @query, \['match('.join(',', @keys).') against(? in boolean mode)', $query.'*'];
                }
                if (exists $options{trigramquery} && $options{trigramquery}) {
                    push @query, trigram_match_against($query, $options{trigramquery});
                }
                my %where = ( -or => \@query );
                $data = $data->search(\%where);
            }
        }
        if (exists $options{qualifiers}) {
            my %where;
            foreach my $name (@{$options{qualifiers}}) {
                my $param = param($name);
                if (defined $param && $param ne '') {
                    my $key = $name =~ m/\./ ? $name : 'me.'.$name;
                    if ($param eq 'null') {
                        $where{$key} = undef;
                    }
                    else {
                        $param =~ m/([>=<]{0,2})(.*)/;
                        my $compare = $1;
                        my $value = $2;
                        if ($compare) {
                            $where{$key} = { $compare => $value };
                        }
                        else {
                            $where{$key} = $value;
                        }
                    }
                }
            }
            $data = $data->search(\%where);
        }
        if (exists $options{ranged}) {
	    my @query = ();
	    foreach my $name (@{$options{ranged}}) {
		my $key = $name =~ m/\./ ? $name : 'me.'.$name;
		my $start = param('_start_'.$name);	
		if (defined $start && $start ne '') {
		    push @query, {$key => { '>=' => $start }};
		}
		my $end = param('_end_'.$name);	
		if (defined $end && $end ne '') {
		    push @query, {$key => { '<=' => $end }};
		}
            }
	    my %where = ( -and => \@query );
            $data = $data->search(\%where);
	}
        return format_list($data, current_user => $current_user);
    };
};

register generate_all_relationships => sub {
    my ($wing_object_type, %options) = @_;
    my $db_class_name = %options && exists $options{db_class_name} ? $options{db_class_name} : $wing_object_type; # creates alias for migrating from old APIs to new
    my $object_parameters = $options{object_parameters} || {};
    my $wing_object = site_db()->resultset($db_class_name)->new($object_parameters);
    foreach my $name (@{$wing_object->relationship_accessors}) {
        my %rel_options;
        if (exists $options{named_options}) {
            if (exists $options{named_options}{$name}) {
                %rel_options = (%{$options{named_options}{$name}});
            }
        }
        if (exists $options{permissions}) {
            $rel_options{permissions} = $options{permissions};
        }
        if (exists $options{db_class_name}) {
            $rel_options{db_class_name} = $options{db_class_name};
        }
        generate_relationship($wing_object_type, $name, %rel_options);
    }
};

# not sure this is entirely necessary, but just want to make sure it is absolutely per request
hook before => sub {
    Wing->stash->reset();
};

hook before_serializer => sub {
    my $response = shift;
    my $content  = $response->{content};
    $response->{content} = { result => $content, };
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
 generate_all_relationships('User');

 1;

=head1 DESCRIPTION

This L<Dancer> plugin generates restful web services from a Wing class definition. It provides a lot of nifty code-generation tools to auto-generate the web services, and also to write your own custom web services.

=head1 SUBROUTINES

=head2 get_session( options )

Unless for some reason you're only mucking around with the session and not the user, you should use C<get_user_by_session_id> instead. Will L<Ouch> a 401 if it can't find a session or the session has expired.

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

=head2 generate_relationship ( object_type, relationship_name, options )

 generate_relationship('User','apikeys'); # GET /api/user/xxx/apikeys

=over

=item object_type

The short version of the class name for a result. So instead of C<MyApp::DB::Result::User> you use C<User>.

=item relationship_name

The name of the relationship to generate. Must be a relationship created using L<Wing::Role::Result::Parent> or L<Wing::Role::Result::Child> or L<Wing::Role::Result::Cousin> or a relationship of your own design that conforms to one of those.

=item options

A hash reference.

=over

=item permissions

See L<Wing::Role::Result::APIKeyPermission>.

=item queryable

An array reference of field names that be queried via wildcard search.

=item qualifiers

An array reference of field names that may be used as a hard limit on a query of this relationship. For example, if the array reference includes C<public>, then there must be a field on the class named C<public> and if the query comes through as C<public = 1> then only the related objects where that is true will be returned.

You can also do other comparison types such as >, >=, <, <=, or <> by prepending the operator on the value like this:

 ?start_date=>=2016-01-07 15:30:00

The first equal sign is the assignment operator and will be processed out. The reminader reads where C<start_date> is greater than or equal to C<2016-01-07 15:30:00>.

=back

=back

=head2 generate_all_relationships ( object_type, options )

 generate_all_relationships('User'); # GET /api/user/xxx/yyy

=over

=item object_type

The short version of the class name for a result. So instead of C<MyApp::DB::Result::User> you use C<User>.

=item options

A hash reference of options.

=over

=item named_options

A hash reference containing the options to pass to C<generate_relationship>.

=item permissions

See L<Wing::Role::Result::APIKeyPermission>.

=bacl

=back

where C<yyy> is any relationship defined using L<Wing::Role::Result::Parent> or L<Wing::Role::Result::Child>.

=head1 SEE ALSO

The subroutines from L<Wing::Dancer> are also imported into here. You should also look at L<Wing::RestUsage> for the output that will be generated by these methods.

=cut

package Wing::Rest;

use strict;
use warnings;
use Ouch;
use Dancer ':syntax';
use Dancer::Plugin;

set serializer => 'JSON';

register get_session => sub {
    my ($session_id) = @_;
    $session_id ||= params->{session_id};
    my $cookie = cookies->{session_id};
    if (!defined $session_id && defined $cookie) {
        $session_id = $cookie->value;
    }
    unless (defined $session_id) {
        ouch 441, 'session_id is required', 'session_id';
    }
    return $session_id if (ref $session_id eq 'Wing::Session');
    my $session = Wing::Session->new( id => $session_id, db => vars->{site_db}, cache => MobRaterManager->cache );
    if ($session->user_id) {
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
        my $max = MobRaterManager->config->get('rpc_limit') || 30;
        if ($user->rpc_count > $max) {
            ouch 452, 'Slow down! You are only allowed to make ('.$max.') requests per minute to the server.', $max;
        }
        return $user;
    }
    else {
        ouch 440, 'User no longer exists.', 'session_id';
    }
};

register fetch_object => sub {
    my ($type, $id) = @_;
    $id ||= params->{id};
    ouch(404, 'No id specified for '.$type) unless $id;
    my $object = vars->{site_db}->resultset($type)->find($id);
    ouch(404, $type.' not found.') unless defined $object;
    return $object;
};

register format_list => sub {
    my $result_set = shift;
    my $page_number = params->{page_number} || 1;
    my $items_per_page = params->{items_per_page} || 25;
    $items_per_page = ($items_per_page < 1 || $items_per_page > 100 ) ? 25 : $items_per_page;
    my $page = $result_set->search(undef, {rows => $items_per_page, page => $page_number });
    my @list;
    my $current_user = eval { get_user_by_session_id() };
    while (my $item = $page->next) {
        push @list, describe($item, $current_user);
    }
    return {
        paging => {
            total_items             => $page->pager->total_entries,
            total_pages             => int($page->pager->total_entries / $items_per_page) + 1,
            page_number             => $page_number,
            items_per_page          => $items_per_page,
            next_page_number        => $page_number + 1,
            previous_page_number    => $page_number < 2 ? 1 : $page_number - 1,
        },
        items   => \@list,
    };
};

register describe => sub {
    my ($object, $current_user) = @_;
    $current_user ||= eval { get_user_by_session_id() };
    return $object->describe(
        include_private         => (eval { $object->can_use($current_user) }) ? 1 : 0,
        include_relationships   => params->{include_relationships},
        include_options         => params->{include_options},
        include_related_objects => params->{include_related_objects},
        current_user            => $current_user,
        tracer                  => get_tracer(),
    );
};

register generate_delete => sub {
    my ($object_type) = @_;
    my $object_url = lc($object_type);
    del '/api/'.$object_url.'/:id'  => sub {
        my $object = fetch_object($object_type);
        $object->can_use(get_user_by_session_id());
        $object->delete;
        return { success => 1 };
    };
};

register get_tracer => sub {
    my $cookie = cookies->{tracer};
    if (defined $cookie) {
        return $cookie->value;
    }
    return undef;
};

register expanded_params => sub {
    my %params = params;
    $params{tracer} = get_tracer();
    $params{ipaddress} = request->env->{HTTP_X_REAL_IP} || request->remote_address;
    $params{useragent} = request->user_agent;
    return \%params
};

register generate_update => sub {
    my ($object_type, $extra_processing) = @_;
    my $object_url = lc($object_type);
    put '/api/'.$object_url.'/:id'  => sub {
        my $current_user = get_user_by_session_id();
        my $object = fetch_object($object_type);
        $object->can_use($current_user);
        $object->verify_posted_params(expanded_params(), $current_user);
        if (defined $extra_processing) {
            $extra_processing->($object, $current_user);
        }
        $object->update;
        return describe($object, $current_user);
    };
};

register generate_create => sub {
    my ($object_type, $extra_processing) = @_;
    my $object_url = lc($object_type);
    post '/api/'.$object_url => sub {
        my $object = vars->{site_db}->resultset($object_type)->new({});
        my $params = expanded_params();
        my $current_user = eval{get_user_by_session_id()};
        $object->verify_creation_params($params, $current_user);
        $object->verify_posted_params($params, $current_user);
        if (defined $extra_processing) {
            $extra_processing->($object, $current_user);
        }
        $object->insert;
        return describe($object, $current_user);
    };
};

register generate_read => sub {
    my ($object_type) = @_;
    my $object_url = lc($object_type);
    get '/api/'.$object_url.'/:id' => sub {
        return describe(fetch_object($object_type));
    };
};

register generate_options => sub {
    my ($object_type) = @_;
    my $object_url = lc($object_type);
    get '/api/'.$object_url.'/options' => sub {
        return vars->{site_db}->resultset($object_type)->new({})->field_options(
            include_relationships   => params->{include_relationships},
            include_options         => params->{include_options},
            include_related_objects => params->{include_related_objects},
            current_user            => eval { get_user_by_session_id() },
        );
    };
};

register generate_crud => sub {
    my ($object_type) = @_;
    generate_options($object_type);
    generate_read($object_type);
    generate_update($object_type);
    generate_delete($object_type);
    generate_create($object_type);
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
        $error->{code} = $error->exception->code;
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

register_plugin;

1;

# this gets included into Wing::Rest and Wing::Web to avoid duplcation of code

use Wing;

register site_db => sub {
    if (exists vars->{wing_site_db} && defined vars->{wing_site_db}) {
        return vars->{wing_site_db};
    }
    my $domain = Wing->config->get('tenants/domain');
    if ($domain) {
        my $hostname = request->env->{HTTP_HOST};
        my $search = {trashed => 0};
        if ($hostname =~ m/^(.*)\.$domain$/) {
            $search->{-or} = [ { shortname => $1 }, {hostname => $hostname} ];
        }
        else {
            $search->{hostname} = $hostname;
        }
        my $site = Wing->db->resultset('Site')->search($search,{rows => 1})->single;
        if (defined $site) {
            site( $site );
            return vars->{wing_site_db} = $site->connect_to_database;
            pass;
        }
    }
    return Wing->db;
};


hook after => sub {
    if (exists vars->{wing_site_db} && defined vars->{wing_site_db}) { # we only need to disconnect if this is a tenant site
        vars->{wing_site_db}->storage->disconnect;
    }
};

register site => sub {
    my ($site) = @_;
    if ($site) {
        var wing_site => $site;
    }
    return vars->{wing_site};
};

register fetch_object => sub {
    my ($type, $id) = @_;
    $id ||= params->{id};
    ouch(404, 'No id specified for '.$type) unless $id;
    my $object = site_db()->resultset($type)->find($id);
    ouch(404, $type.' not found.') unless defined $object;
    return $object;
};

register format_list => sub {
    my ($result_set, %options) = @_;
    my $page_number = $options{page_number} || params->{page_number} || 1;
    my $items_per_page = $options{items_per_page} || params->{items_per_page} || 25;
    $items_per_page = ($items_per_page < 1 || $items_per_page > 100 ) ? 25 : $items_per_page;
    my $page = $result_set->search(undef, {rows => $items_per_page, page => $page_number });
    my @list;
    my $user = eval{ get_user_by_session_id() };
    my $tracer = get_tracer();
    while (my $item = $page->next) {
        push @list, $item->describe(
            include_admin           => $options{include_admin} || (defined $user && $user->is_admin) ? 1 : 0, 
            include_private         => $options{include_private} || (eval { $item->can_use($user) }) ? 1 : 0, 
            include_relationships   => $options{include_relationships} || params->{include_relationships}, 
            include_related_objects => $options{include_related_objects} || params->{include_related_objects}, 
            include_options         => $options{include_options} || params->{include_options}, 
            tracer                  => $tracer,
            current_user            => $user,
        );
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



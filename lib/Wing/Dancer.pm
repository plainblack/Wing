# this gets included into Wing::Rest and Wing::Web to avoid duplcation of code

=head1 NAME

Wing::Dancer - A mixin of Dancer utilities.

=head1 DESCRIPTION

These subroutines get included into L<Wing::Rest> and L<Wing::Web>. These subs are shared between the two do avoid duplication of code.

=cut

use Wing;
use POSIX qw/ceil/; 
use Data::GUID;

=head1 SUBROUTINES

=head2 find_tenant_site()

When Wing is running in multi-tenant mode, this subroutine can be used to look up a site record. See L<Wing::Role::Result::Site> for details.  If a site record is found, it will set the Dancer variable C<is_tenant>.

=cut

sub find_tenant_site {
    my $domain = Wing->config->get('tenants/domain');
    var is_tenant => 0;
    return undef unless $domain;
    my $hostname = request->env->{HTTP_HOST};
    my $search = {trashed => 0};
    if ($hostname =~ m/^(.*)\.$domain$/) {
        $search->{-or} = [ { shortname => $1 }, {hostname => $hostname} ];
    }
    else {
        $search->{hostname} = $hostname;
    }
    my $tenant = Wing->db->resultset('Site')->search($search,{rows => 1})->single;
    var is_tenant => defined $tenant ? 1 : 0;
    return $tenant;
}

=head2 site_db()

In multi-tenant mode, this returns the a reference to the database for the current site. Otherwise it returns Wing->db.

Registered as a Dancer keyword.

=cut

register site_db => sub {
    if (exists vars->{wing_site_db} && defined vars->{wing_site_db}) {
        return vars->{wing_site_db};
    }
    my $domain = Wing->config->get('tenants/domain');
    my $tenant = find_tenant_site();
    if (vars->{is_tenant}) {
        site( $tenant );
        var wing_site_db => $tenant->connect_to_database;
        return vars->{wing_site_db};
    }
    return Wing->db;
};


hook after => sub {
    if (exists vars->{wing_site_db} && defined vars->{wing_site_db}) { # we only need to disconnect if this is a tenant site
        vars->{wing_site_db}->storage->disconnect;
    }
};

=head2 site()

Returns a site record. This is the value of find_tenant_site(), except calling through this is cached, and therefore faster.

Registered as a Dancer keyword.

=cut

register site => sub {
    my ($site) = @_;
    if ($site) {
        var wing_site => $site;
    }
    elsif (!exists vars->{wing_site} || !defined vars->{wing_site}) {
        $site = find_tenant_site();
        var wing_site => $site;
    }
    return vars->{wing_site};
};

=head2 fetch_object(class, id)

Returns a Wing object of the specified type.

Registered as a Dancer keyword.

=over

=item class

Required. The class name of the object you wish to fetch.

=item id

Optional. The id of the object you wish to fetch. Defaults to pulling the id from Dancer C<params>.

=back

=cut

register fetch_object => sub {
    my ($type, $id) = @_;
    $id ||= params->{id};
    ouch(404, 'No id specified for '.$type) unless $id;
    my $object = site_db()->resultset($type)->find($id);
    ouch(404, $type.' not found.') unless defined $object;
    return $object;
};

=head format_list(result_set, options)

Formats a result set as a hash reference for exposing to web/rest.

Registered as a Dancer keyword.

=over

=item result_set

A result set to format.

=item options

A hash of formatting options.

=over

=item page_number

Defaults to C<params> _page_number, or 1 if not specified.

=item items_per_page

A number between 1 and 100. Defaults to C<params> _items_per_page or 25 if not specified.

=item include_admin

If you want to force the items in the formatted list to include admin fields.

=item include_private

If you want to force the items in the formatted list to include private fields.

=item include_related_objects

If you want to force the items in the formatted list to include related objects.

=item include_relationships

If you want to force the items in the formatted list to include relationships.

=item include_options

If you want to force the items in the formatted list to include field options.

=item object_options

If you need to pass additional object-specific options to the object, pass them in here. Is a hash reference.

=back

=back

=cut

register format_list => sub {
    my ($result_set, %options) = @_;
    my $page_number = $options{page_number} || params->{_page_number} || 1;
    my $items_per_page = $options{items_per_page} || params->{_items_per_page} || 25;
    $items_per_page = ($items_per_page < 1 || $items_per_page > 100 ) ? 25 : $items_per_page;
    my $page = $result_set->search(undef, {rows => $items_per_page, page => $page_number });
    my @list;
    my $user = $options{current_user} || eval{ get_user_by_session_id() };
    my $is_admin = defined $user && $user->is_admin ? 1 : 0;
    while (my $item = $page->next) {
        push @list, $item->describe(
            %{ (exists $options{object_options} ? $options{object_options} : {}) },
            include_admin           => $options{include_admin} || $is_admin ? 1 : 0, 
            include_private         => $options{include_private} || (eval { $item->can_view($user) }) ? 1 : 0, 
            include_relationships   => $options{include_relationships} || params->{_include_relationships}, 
            include_related_objects => $options{include_related_objects} || params->{_include_related_objects}, 
            include_options         => $options{include_options} || params->{_include_options}, 
            tracer                  => get_tracer(),
            current_user            => $user,
        );
    }
    return {
        paging => {
            total_items             => $page->pager->total_entries,
            total_pages             => ceil($page->pager->total_entries / $items_per_page),
            page_number             => $page_number,
            items_per_page          => $items_per_page,
            next_page_number        => $page_number + 1,
            previous_page_number    => $page_number < 2 ? 1 : $page_number - 1,
        },
        items   => \@list,
    };
};


=head2 describe ( object, options )

Returns the description of the object by calling it's C<describe> method. However, it also gracefully handles all the extra modifiers such as _include_relationships and displaying private information if the user owns the object.

=over

=item object

The object you wish to describe.

=item options

=over

=item current_user

Optional. If specified we won't bother trying to figure out who the current user is.

=item include_admin

If you want to force the items in the description to include admin fields.

=item include_private

If you want to force the items in the description to include private fields.

=item include_related_objects

If you want to force the items in the description to include related objects.

=item include_relationships

If you want to force the items in the description to include relationships.

=item include_options

If you want to force the items in the description to include field options.

=item object_options

If you need to pass additional object-specific options to the object, pass them in here. Is a hash reference.

=back

=back

=cut

register describe => sub {
    my ($object, %options) = @_;
    my $current_user = $options{current_user} || eval { get_user_by_session_id() };
    return $object->describe(
        %{ (exists $options{object_options} ? $options{object_options} : {}) },
        include_private         => $options{include_private} || (eval { $object->can_view($current_user) }) ? 1 : 0,
        include_admin           => $options{include_admin} || (eval { defined $current_user && $current_user->is_admin }) ? 1 : 0,
        include_relationships   => $options{include_relationships} || params->{_include_relationships},
        include_options         => $options{include_options} || params->{_include_options},
        include_related_objects => $options{include_related_objects} || params->{_include_related_objects},
        current_user            => $current_user,
        tracer                  => $options{tracer} || get_tracer(),
    );
};

=head2 get_tracer()

Returns a tracer id. Tracers are used to track users when no user session is present.

Registered as a Dancer keyword.

=cut

register get_tracer => sub {
    my $cookie = cookies->{tracer};
    if (defined $cookie) {
        return $cookie->value;
    }
    return undef;
};

=head2 expanded_params()

Does the same thing as Dancer C<params> but also added a few new automatic keys: C<tracer>, C<ipaddress>, C<useragent>

Registered as a Dancer keyword.

=cut

register expanded_params => sub {
    my %params = params;
    $params{tracer} = get_tracer();
    $params{ipaddress} = request->env->{HTTP_X_REAL_IP} || request->remote_address;
    $params{useragent} = request->user_agent;
    return \%params
};

=head2 track_user()

Attempt to track users by setting a cookie, without requiring the user to log in.

=cut

register track_user => sub {
    my $cookie = cookies->{tracer};
    my $tracer;
    if (defined $cookie) {
        $tracer = $cookie->value;
    }
    else {
        $tracer = Data::GUID->new->as_string;
        set_cookie tracer       => $tracer,
            expires             => '+5y',
            http_only           => 0,
            path                => '/';
    }
    return ($tracer, eval{get_user_by_session_id()});
};


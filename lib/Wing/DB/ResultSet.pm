package Wing::DB::ResultSet;

use Moose;
extends 'DBIx::Class::ResultSet';
use POSIX qw/ceil/;

sub BUILDARGS { $_[2] }

=head1 NAME

Wing::DB::ResultSet - A base class for result sets.

=head1 SYNOPSIS

 my $users = Wing->db->resultset('User')->search(undef, { order_by => 'email' });
 my $hashref = $users->format_list(current_user => $user, include_related_objects => 1);

=head1 DESCRIPTION



=head1 METHODS

=head2 format_list(options)

Formats a result set as a hash reference with pagination options. This is most often returned to a rest call or a template for display.

=over

=item options

A hash of formatting options.

=over

=item current_user

The user who is logged logged in to the site currently, if any.

=item tracer

An id used for tracking anonymous users. See C<get_tracer> in L<Wing::Dancer>.

=item page_number

Defaults to 1 if not specified.

=item items_per_page

A number between 1 and 100. Defaults to 25 if not specified.

=item max_items

Defaults to 100,000,000,000. May be used to artificially limit a multi-page result set to an arbitrary number rather than paginating through all records in the database that match the query.

=item include_admin

If you want to force the items in the formatted list to include admin fields. Will be included automatically if the C<current_user> is an admin.

=item include_private

If you want to force the items in the formatted list to include private fields. They will be included automatically if the C<current_user> can view the object.

=item include_related_objects

If you want to force the items in the formatted list to include related objects. If you want to include specific objects then pass an array reference of the relationship names of those objects.

=item include_relationships

If you want to force the items in the formatted list to include relationships.

=item include

An array reference that will be passed to your object and you can use that to include arbitrary data by adding custom stuff to your class's C<describe()> method.

=item include_options

If you want to force the items in the formatted list to include field options.

=item order_by

The field to order by. Defaults to whatever order C<result_set> would normally have. This can also be an array reference if you want to order by multiple fields. You can also use related objects to sort by specifying a related object name and a dot before the field name like C<related.field>.

=item sort_order

Must be C<asc> or C<desc>. Defaults to whatever sorder order C<result_set> would normally have. If C<order_by> isn't specified then this is ignored.

=item describe_lite

Use a light-weight object describer, instead of C<describe> with all of its side-effects.

=item object_options

If you need to pass additional object-specific options to the object, pass them in here. Is a hash reference.

=back

=back

=back

=cut

sub format_list {
    my ($self, %options) = @_;

    # set defaults
    my $page_number = $options{page_number} || 1;
    my $items_per_page = $options{items_per_page} || 25;
    my $max_items = $options{max_items} || 100_000_000_000;
    $items_per_page = ($items_per_page < 1 || $items_per_page > 100 ) ? 25 : $items_per_page;
    my $max_items_this_page = $items_per_page;
    my $items_up_to_this_page = $items_per_page * $page_number;
    my $full_pages = int($max_items / $items_per_page);
    my $skip_result_set = 0;
    if ($items_up_to_this_page - $items_per_page >= $max_items) {
        $skip_result_set = 1;
    }
    elsif ($page_number - $full_pages == 1) {
        $max_items_this_page = $items_per_page - ($items_up_to_this_page - $max_items);
    }
    elsif ($page_number - $full_pages > 1) {
        $skip_result_set = 1;
    }
    my @list;
    my $user = $options{current_user};
    my $is_admin = defined $user && $user->is_admin ? 1 : 0;
    my $extra = {rows => $items_per_page, page => $page_number };
    my $prefetch = [];

    # handle related objects
    my $include_related_objects = $options{include_related_objects};
    if (defined $include_related_objects) {
        if (ref $include_related_objects ne 'ARRAY' && $include_related_objects !~ m/^\d$/) { # make related objects an array
            $include_related_objects = [$include_related_objects];
        }
        if (ref $include_related_objects eq 'ARRAY') { # handle prefetch
            $prefetch = $include_related_objects;
        }
    }

    # ordering
    if (exists $options{order_by} && $options{order_by}) {
        my $order_by = $options{order_by};
        if (ref $order_by ne 'ARRAY') {
            $order_by = [$order_by];
        }
        for (my $i = scalar(@{$order_by}) - 1; $i >= 0; $i--) {

            unless ($order_by->[$i] =~ m/^[a-z0-9\.\_]+$/i) { # disregard poorly formatted requests
                delete $order_by->[$i];
                next;
            }

            if ($order_by->[$i] !~ m/\./) {
                $order_by->[$i] = 'me.'.$order_by->[$i];
            }
            elsif ($order_by->[$i] =~ m/^(.*)\./) {
                if ($1 ne 'me') {
                    unless ($1 ~~ $prefetch) {
                        push @{$prefetch}, $1;
                    }
                }
            }
        }
        $extra->{order_by} = $order_by;
    }
    if (exists $extra->{order_by} && $extra->{order_by} && exists $options{sort_order} && defined $options{sort_order} && $options{sort_order} eq 'desc') {
        $extra->{order_by} = { -desc => $extra->{order_by} };
    }

    # perform the search
    if (scalar @{$prefetch}) {
        $extra->{prefetch} = $prefetch;
    }
    my $page = $self->search(undef, $extra);
    my $describe_method = $options{describe_lite} ? 'describe_lite' : 'describe';
    unless ($skip_result_set) {
        while (my $item = $page->next) {
            push @list, $item->$describe_method(
                %{ (exists $options{object_options} ? $options{object_options} : {}) },
                include_admin           => $options{include_admin} || $is_admin ? 1 : 0,
                include_private         => $options{include_private} || (eval { $item->can_view($user) }) ? 1 : 0,
                include_relationships   => $options{include_relationships},
                include_related_objects => $include_related_objects,
                include                 => $options{include},
                include_options         => $options{include_options},
                tracer                  => $options{tracer},
                current_user            => $user,
            );
            $max_items_this_page--;
            last if ($max_items_this_page < 1);
        }
    }
    my $total_items = $page->pager->total_entries;
    if ($total_items > $max_items) {
        $total_items = $max_items;
    }

    # format output
    return {
        paging => {
            total_items             => $total_items,
            total_pages             => ceil($total_items / $items_per_page),
            page_number             => $page_number,
            items_per_page          => $items_per_page,
            next_page_number        => $page_number + 1,
            previous_page_number    => $page_number < 2 ? 1 : $page_number - 1,
        },
        items   => \@list,
    };
}


no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);

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

=item include_admin

If you want to force the items in the formatted list to include admin fields. Will be included automatically if the C<current_user> is an admin.

=item include_private

If you want to force the items in the formatted list to include private fields. They will be included automatically if the C<current_user> can view the object.

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

sub format_list {
    my ($self, %options) = @_;
    my $page_number = $options{page_number} || 1;
    my $items_per_page = $options{items_per_page} || 25;
    $items_per_page = ($items_per_page < 1 || $items_per_page > 100 ) ? 25 : $items_per_page;
    my @list;
    my $user = $options{current_user};
    my $is_admin = defined $user && $user->is_admin ? 1 : 0;
    my $page = $self->search(undef, {rows => $items_per_page, page => $page_number });
    while (my $item = $page->next) {
        push @list, $item->describe(
            %{ (exists $options{object_options} ? $options{object_options} : {}) },
            include_admin           => $options{include_admin} || $is_admin ? 1 : 0, 
            include_private         => $options{include_private} || (eval { $item->can_view($user) }) ? 1 : 0, 
            include_relationships   => $options{include_relationships}, 
            include_related_objects => $options{include_related_objects}, 
            include_options         => $options{include_options}, 
            tracer                  => $options{tracer},
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
}


no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);

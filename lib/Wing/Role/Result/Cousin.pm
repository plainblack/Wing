package Wing::Role::Result::Cousin;

use Wing::Perl;
use Ouch;
use Moose::Role;

sub wing_cousin_relationship {
    my ($class, $field, $options) = @_;

    # create relationship
    $class->meta->add_after_method_modifier(wing_apply_relationships => sub {
        my $my_class = shift;
        $my_class->many_to_many($field => $options->{related_link}, $options->{related_cousin});
    });
   
    # make note of the relationship
    $class->meta->add_around_method_modifier(relationship_accessors => sub {
        my ($orig, $self) = @_;
        my $params = $orig->($self);
        push @$params, $field;
        return $params;
    });

    # add relationship to describe
    $class->meta->add_around_method_modifier(describe => sub {
        my ($orig, $self, %describe_options) = @_;
        my $out = $orig->($self, %describe_options);
        my $describe = sub {
            if ($describe_options{include_relationships}) {
                $out->{_relationships}{$field} = '/api/'.$self->wing_object_type.'/'.$self->id.'/'.$field;
            }
            return $out;
        };
        if (exists $options->{view}) {
            if ($options->{view} eq 'admin') {
                $describe->() if $describe_options{include_admin};
            }
            elsif ($options->{view} eq 'private') {
                $describe->() if $describe_options{include_private};
            }
            elsif ($options->{view} eq 'public') {
                $describe->(); 
            }
        }
        return $out;
    });
}

sub wing_cousins {
    my ($class, %fields) = @_;
    while (my ($field, $options) = each %fields) {
        $class->wing_cousin_relationship($field, $options);
    }
}

sub wing_cousin {
    my ($class, $field, $options) = @_;
    $class->wing_cousin_relationship($field, $options);
}

1;

=head1 NAME

Wing::Role::Result::Cousin

=head1 DESCRIPTION

Create many to many relationships using a linking class.

=head1 SYNOPSIS

You'll use Wing::Role::Result::Cousin in both classes you want to link together through a linking class. For example, let's say you have a class called Smith and another Brown. You'd create a linking class called SmithBrown.

My first class is Smith:

 package MyApp::DB::Result::Smith;

 extends 'Wing::DB::Result';
 with 'Wing::Role::Result::Child';
 with 'Wing::Role::Result::Cousin';

 __PACKAGE__->wing_children(
    smithbrowns => {
        view           => 'public',
        related_class  => 'MyApp::DB::Result::SmithBrown',
        related_id     => 'smith_id',
    }
 );

 __PACKAGE__->wing_cousins(
    browns => {
        view            => 'public',
        related_link    => 'smithbrowns',
        related_cousin  => 'brown',
    },  
 );

 __PACKAGE__->wing_finalize_class( table_name => 'smiths');

 1;

My second class is Brown:

 package MyApp::DB::Result::Brown;

 extends 'Wing::DB::Result';
 with 'Wing::Role::Result::Child';
 with 'Wing::Role::Result::Cousin';

 __PACKAGE__->wing_children(
    smithbrowns => {
        view           => 'public', # delete to make this relationship inaccessable via Rest
        related_class  => 'MyApp::DB::Result::SmithBrown',
        related_id     => 'brown_id',
    }
 );

 __PACKAGE__->wing_cousins(
    smiths => {
        view            => 'public',
        related_link    => 'smithbrowns',
        related_cousin  => 'smith',
    },  
 );

 __PACKAGE__->wing_finalize_class( table_name => 'browns');

 1;

Notice the only thing different between them, other than the C<wing_cousins> relationship, are the package names and the C<related_id> field. Then my linking class looks like this:

 package MyApp::DB::Result::SmithBrown;

 extends 'Wing::DB::Result';
 with 'Wing::Role::Result::Parent';

 __PACKAGE__->wing_parents(
    smith    => {
        view            => 'public',
        edit            => 'required',
        related_class   => 'MyApp::DB::Result::Smith',
    },  
    brown => {
        view           => 'public',
        edit           => 'required',
        related_class  => 'MyApp::DB::Result::Brown',
    },  
);

 __PACKAGE__->wing_finalize_class( table_name => 'smithbrowns');

 around can_edit => sub {
    my ($orig, $self, $user) = @_; 
    return 1 if $self->badgetype->can_edit($user);
    return $orig->($self, $user);
 };

 1;

The linking class just sets up a many to many relationship between the other two classes.

=head1 METHODS

=head2 wing_cousin

=over

=item name

Scalar. The name of the relationship.

=item options

Hash reference. 

=over

=item view

Must be either undefined or one of C<public>, C<private>, or C<admin>.

=item related_link

Scalar. The accessor name for the linking class.

=item related_cousin

Scalar. The accessor name in the linking class for the class you wish to link to this one.

=back

=back

=head2 wing_cousin

The same as C<wing_cousin>, but takes a hash of relationships rather than just a single one.

=over

=item relationships

Hash. The names are the names of the relationships and the values are the C<options> from C<wing_cousin>.

=back

=cut

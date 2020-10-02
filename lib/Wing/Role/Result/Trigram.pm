package Wing::Role::Result::Trigram;

use Wing::Perl;
use Ouch;
use Data::GUID;
use Moose::Role;
use Wing::Util qw(generate_trigram_from_string trigram_match_against);

with 'Wing::Role::Result::Field';
requires 'trigram_index_fields';

=head1 NAME

Wing::Role::Result::Trigram - Fast substring searches on large tables.

=head1 SYNOPSIS

 use constant trigram_index_fields => ['name'];
 with 'Wing::Role::Result::Trigram';

=head1 DESCRIPTION

Uses MySQL's fulltext engine to create an n-gram search or more specificall a tri-gram search. This allows you to search for substrings on large tables like you would with a normal SQL LIKE, but do it much faster than you normally could. Also because it's using fulltext, it will automatically return the results in relevancy order if you don't include an order by clause. 

=head1 CAVEATS

By default it returns things in a relevancy order. If you add an order by clause to your query then it will have to reorder the results, which can be pretty slow. 

Trigram searches entirely ignore non-word characters. Therefore you cannot use it to search punctuation. 

=head1 REQUIREMENTS

The class you load this into must define a constant with the fields that will be used in the trigram index as an array ref.

=head1 ADDS

=head2 Fields

=over

=item trigram_search 

A C<mediumtext> type field to hold the trigram search data.

=back

=head2 Attributes

=over

=item trigram_fields_updated

Returns either C<0> or C<1> depending upon whether the fields identified in C<trigram_index_fields> have been updated. This triggers the C<trigram_search> field to be updated from the C<trigram_index_fields> just before insert or update.

=back

=head2 Indexes

=over

=item idxft_trigram_search

A C<fulltext> index that will be used to conduct the actual search.

=back

=head2 Methods

=over

=item populate_trigram_search()

Updates the C<trigram_search> field with the values from the fields defined in C<trigram_index_fields>. Returns returns C<$self> so you can call C<insert> or C<update> on it immediately if you have no further changes.

=back

=head1 SEE ALSO

L<Wing::Rest> has a function called C<generate_relationship> (or C<generate_all_relationships>) that has a parameter called C<named_options>. In there you can specify a C<trigramquery> element which will allow you perform a search on a relationship with this role.

L<Wing::Util> has two helper functions called C<trigram_match_against> and C<generate_trigram_from_string>

 generate_all_relationships('SomeClass', named_options => {
     somekids => { trigramquery => 'me' },
 });

L<Wing::Command::Command::db>

You can use the C<wing> command line interface to index or re-index a trigram like this

 wing db --index-trigram=SomeClass

=cut


before wing_finalize_class => sub {
    my ($class) = @_;
    $class->wing_field(
        trigram_search => {
            dbic            => { data_type => 'mediumtext', is_nullable => 0 },
        }
    );
    $class->meta->add_around_method_modifier(sqlt_deploy_hook => sub {
	my ($orig, $self, $sqlt_table) = @_;
	$orig->($self, $sqlt_table);
	$sqlt_table->add_index(name => 'idxft_trigram_search', fields => ['trigram_search'], type => 'fulltext');
    });
};

after wing_finalize_class => sub {
    my $class = shift;
    foreach my $field (@{$class->trigram_index_fields}) {
        $class->meta->add_before_method_modifier($field, sub {
            if (scalar @_ == 2 && defined $_[1]) {
                $_[0]->trigram_fields_updated(1);
            }
        });
    }
};

has trigram_fields_updated => (
	is      => 'rw',
    default => 0,
);

before insert => sub { $_[0]->populate_trigram_search };
before update => sub { $_[0]->populate_trigram_search };

sub populate_trigram_search {
    my $self = shift;
    my $string;
    foreach my $field (@{$self->trigram_index_fields}) {
        my $value = $self->$field();
        if (defined $value) {
            $string .= $value . ' ';
        }
    }
    $self->trigram_search(generate_trigram_from_string($string));
    return $self;
}

1;
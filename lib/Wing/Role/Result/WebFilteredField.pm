package Wing::Role::Result::WebFilteredField;

use Moose::Role;
use Wing::Perl;
use Ouch;
use Wing::ContentFilter;

with 'Wing::Role::Result::Field';

sub wing_webfiltered_fields {
    my ($class, %fields) = @_;
    while (my ($field, $definition) = each %fields) {
        $class->wing_webfiltered_field($field, $definition);
    }
}

sub wing_webfiltered_field {
    my ($object_class, $field, $options) = @_;

    my %dbic = ( data_type => 'mediumtext', is_nullable => 1 );
    $options->{dbic} = \%dbic;
    $object_class->wing_field($field, $options);

    my $field_html = $field.'_html';
    $object_class->wing_field($field_html, {
        dbic    => \%dbic,
        view    => 'public',
    });
    
    $object_class->meta->add_after_method_modifier(wing_apply_fields => sub {
        my ($class) = @_;
        $class->meta->add_before_method_modifier($field => sub {
            my ($self, $value) = @_;
            if (defined $value) {
                my @unsorted = split /\s+/, $value;
                my @sorted = map {$_->[1]} sort {$a->[0] <=> $b->[0]} map {[length $_, $_]} @unsorted;
                if (length($sorted[-1]) > 200) {
                    ouch 442, $sorted[-1].', in '.$field.' is too long. 200 characters max.', $field;
                }
                my $html = $value;
                Wing::ContentFilter::format_html(\$html, { entities => 1 });
                Wing::ContentFilter::find_and_format_uris(\$html, { youtube => 1, links => 1, images => 1, vimeo => 1});
                $self->$field_html($html);
            }
        });
    });
}

1;

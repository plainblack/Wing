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
                my $html = $value;
                Wing::ContentFilter::format_html(\$html, exists $options->{format_html} ? $options->{format_html} : { entities => 1, with_markdown => $options->{use_markdown} });
                Wing::ContentFilter::find_and_format_uris(\$html, exists $options->{find_and_format_uris} ? $options->{find_and_format_uris} : { youtube => 1, links => 1, images => 1, vimeo => 1});

                if ($options->{use_markdown}) {
                    Wing::ContentFilter::format_markdown(\$html);
                }
                $self->$field_html($html);
            }
        });
    });
}

1;

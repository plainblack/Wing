package Wing::Role::Result::JSONField;

use Wing::Perl;
use Ouch;
use Moose::Role;
with 'Wing::Role::Result::Field';
use JSON;

=head1 NAME

Wing::Role::Result::JSONField - Inflate JSON into Perl data structures.

=head1 SYNOPSIS

 with 'Wing::Role::Result::JSONField';
 
 __PACKAGE__->wing_json_fields(
    custom_fields => {},
 );

=head1 DESCRIPTION

Using this role will allow you to inflate and deflate JSON blobs  into Perl data structures automatically. 
 
=cut

sub wing_json_fields {
    my ($class, %fields) = @_;
    while (my ($field, $definition) = each %fields) {
        $class->wing_json_field($field, $definition);
    }
}

sub wing_json_field {
    my ($object_class, $field, $options) = @_;

    my %dbic = ( data_type => 'mediumblob', is_nullable => 1, 'serializer_class' => 'JSON', 'serializer_options' => { utf8 => 1 } );
    $options->{dbic} = \%dbic;
    $object_class->wing_field($field, $options);

    $object_class->meta->add_after_method_modifier(wing_apply_fields => sub {
        my ($class) = @_;
        $class->meta->add_around_method_modifier($field => sub {
            if (scalar @_ == 3 && defined $_[2]) {
                my ($orig, $self, $json) = @_;
                my $perl = eval { from_json($json) };
                if ($@) {
                    my $error = $@;
                    $error =~ m/^(.*)\sat\s.*/; 
                    my $help = $1;
                    Wing->log->warn($field.': '. $error);
                    ouch 442, 'Invalid JSON for '.$field.': '.$help, $field;
                }
                else {
                    return $self->$orig($perl);
                }
            }
            return $_[0]->($_[1]);
        });
    });

}

1;

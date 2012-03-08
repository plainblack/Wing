package Wing::Role::Result::UriPart;

use Wing::Perl;
use Ouch;
use Moose::Role;
use Data::GUID;
requires 'name';

before wing_finalize_class => sub {
    my ($class) = @_;
    $class->wing_field(
        uri_part => {
            dbic        => { data_type => 'varchar', size => 60, is_nullable => 0 },
            view        => 'public',
            indexed     => 'unique',
        }
    );
};

after wing_finalize_class => sub {
    my $class = shift;
    $class->meta->add_after_method_modifier('name', sub {
        my ($self, $name) = @_;
        if ($name) {
            # convert into a url
            my $uri_part = lc($name);
            $uri_part =~ s{^\s+}{};          # remove leading whitespace
            $uri_part =~ s{\s+$}{};          # remove trailing whitespace
            $uri_part =~ s{^/+}{};           # remove leading slashes
            $uri_part =~ s{/+$}{};           # remove trailing slashes
            $uri_part =~ s{[^\w/:.-]+}{-}g;  # replace anything aside from word or other allowed characters with dashes
            $uri_part =~ tr{/-}{/-}s;        # replace multiple slashes and dashes with singles.
            if ($uri_part =~ m/^\s+$/) {
                ouch 443, 'That name is not available because it contains too few word characters.', 'name';
            }
    
            # deal with duplicates
            my $objects = $self->result_source->schema->resultset($class);
            if ($self->in_storage) {
                $objects = $objects->search({ id => { '!=' => $self->id }});
            }
            my $counter = '';
            my $shrink = sub {
                my $total_length = length($uri_part) + length($counter);
                if ($total_length > 60) {
                    my $overage = $total_length - 58;
                    $uri_part = substr($uri_part, 0, $total_length - $overage);
                }
            };
            $shrink->();
            while ($objects->search({ uri_part => $uri_part.$counter })->count) {
                $counter++;
                $shrink->();
            }
            $uri_part .= $counter;
            
            # yay, we're ready
            $self->uri_part($uri_part);
        }
    });
};

1;

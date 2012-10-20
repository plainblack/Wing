package Wing::Rest::User;

use Wing::Perl;
use Dancer;
use Ouch;
use Wing::Rest;


get '/api/status' => sub {
    return {
        datetime    => Wing->to_RFC3339,
    }
};

any qr{/api/_test.*} => sub {
    my $out = { 
        method => request->method, 
        params => {params},
        path    => request->path,
    };
    delete $out->{params}{splat};
    my $uploads = request->uploads;
    if (scalar(keys %{$uploads})) {
        foreach my $upload (values %{$uploads}) {
            push @{$out->{uploads}}, {
                filename => $upload->filename,
                size => $upload->size,
                type => $upload->type,
            };
        }
    }
    return $out;
};

1;

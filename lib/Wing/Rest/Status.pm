package Wing::Rest::Status;

use Wing::Perl;
use Dancer;
use Ouch;
use Wing::Rest;
use Data::GUID;


get '/api/status' => sub {
    return {
        datetime    => Wing->to_mysql,
    }
};

any qr{/api/_test.*} => sub {
    my $cookie = cookies->{tracer};
    my $tracer;
    if (defined $cookie) {
        $tracer = $cookie->{value}->[0];
    }
    else {
        $tracer = Data::GUID->new->as_string;
        set_cookie tracer       => $tracer,
            expires           => '+5y',
            http_only         => 0,
            path              => '/';
    }
    my $out = { 
        method  => request->method,
        params  => {params},
        env     => \%ENV,
        path    => request->path,
        tracer  => $tracer,
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

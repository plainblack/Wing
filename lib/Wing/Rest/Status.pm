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
    my $dancer_env = request->env;
    my %env = (
        SERVER_NAME => $dancer_env->{SERVER_NAME},
        HTTP_ACCEPT => $dancer_env->{HTTP_ACCEPT},
        HTTP_USER_AGENT => $dancer_env->{HTTP_USER_AGENT},
        QUERY_STRING => $dancer_env->{QUERY_STRING},
        SERVER_PROTOCOL => $dancer_env->{SERVER_PROTOCOL},
        REQUEST_URI => $dancer_env->{REQUEST_URI},
    );
    my $out = { 
        method  => request->method,
        params  => {params},
        env     => \%env,
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

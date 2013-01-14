#!/usr/bin/env perl
use lib '/data/[% project %]/lib', '/data/Wing/lib';

use Dancer;
# your modules here
use Wing::Web::Account;
use Wing::Web::Admin::User;
use Wing::Web::NotFound;
use Plack::Builder;

my $app = sub {
    my $env = shift;
    $env->{'psgix.harakiri'} = 1;
    my $request = Dancer::Request->new(env => $env);
    Dancer->dance($request);
};

builder {
    unless ($^O eq 'darwin') {
        enable "Plack::Middleware::SizeLimit" => (
            max_unshared_size_in_kb => '51200', # 50MB
            # min_shared_size_in_kb => '8192', # 8MB
            max_process_size_in_kb => '179200', # 175MB
            check_every_n_requests => 3
        );
    }
    enable 'MethodOverride', header => 'X-HTTP-Method', param => 'X-HTTP-Method';
    $app;
};

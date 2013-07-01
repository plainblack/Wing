package TestHelper;

use Dancer;
use Dancer::Request;
use Dancer::Test appdir => '../lib';
use Plack::Test;
use Dancer::Handler;
use Ouch;
use HTTP::Request::Common;

use Wing;
use Wing::Perl;
use Wing::Rest::Session;
use Test::Wing::Client;

our $DEBUG = 1;

sub init {
    my $wing = shift;
    my $andy = Wing->db->resultset('User')->new({
        username    => 'andy',
        real_name   => 'Andy Dufresne',
        email       => 'andy@shawshank.jail',
        admin       => 1,
        developer   => 1,
        use_as_display_name => 'real_name', 
    });
    $andy->encrypt_and_set_password('Saywatanayo');
    $andy->insert;    
    my $key = Wing->db->resultset('APIKey')->new({user_id => $andy->id, name => 'Key for Andy', })->insert;
    
    my $result = $wing->post('session', { username => 'andy', password => 'Saywatanayo', api_key_id => $key->id, _include_related_objects => 1 });
    use Data::Dumper;
    warn Dumper $result;
    print Wing->cache->get('session'.$result->{id});
    print "\n";
    return $result;
}

sub call {
    my ($method, $path, $params) = @_;
    my $content = exists $params->{file} ? call_via_plack_test($method, $path, $params) : call_via_dancer_test($method, $path, $params);
    say $content if $DEBUG;
    my $out = eval{from_json($content)};
    die "got garbage back from ".$method." ".$path." (".to_json($params)."): ".$content if ($@);
    return $out;
}

sub call_via_dancer_test {
    my ($method, $path, $params) = @_;
    my $response = eval{dancer_response $method => $path, { params => $params }};
    say bleep if $@;
    return $response->{content};
}

sub call_via_plack_test { # for file uploads
    my ($method, $path, $params) = @_;
    my $app = Dancer::Handler->get_handler->psgi_app;
    my $content;
    test_psgi $app, sub {
        my $cb = shift;
        my $request = POST $path, Content_Type => 'form-data', Content => [%{$params}];
        $request->method($method);
        my $response = $cb->($request);
        $content = $response->content;
    };
    return $content;
}

sub cleanup {
    my $users = Wing->db->resultset('User');
    while (my $user = $users->next) {
       $user->delete unless $user->username eq 'Admin';
    }
}


1;

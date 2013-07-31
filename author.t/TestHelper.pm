package TestHelper;

use Wing;
use Wing::Perl;

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

sub cleanup {
    my $users = Wing->db->resultset('User');
    while (my $user = $users->next) {
       $user->delete unless $user->username eq 'Admin';
    }
}


1;

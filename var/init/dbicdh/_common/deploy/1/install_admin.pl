sub {
    my $db = shift;
    use 5.12.0;
    say "adding admin";

    my $admin = $db->resultset('User')->new({});
    $admin->username('Admin');
    $admin->admin(1);
    $admin->encrypt_and_set_password('123qwe');
    $admin->insert;

    say "done adding admin...creating api key";

    my $key = $db->resultset('APIKey')->new({});
    $key->name('[% project %]');
    $key->user_id($admin->id);
    $key->insert;
    Wing->config->set('default_api_key', $key->id);

    say "done creating api key...";
}

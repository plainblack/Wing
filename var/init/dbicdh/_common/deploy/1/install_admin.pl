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
    $key->id('WEB000123456789012345678901234567890');
    $key->name('[% project %]');
    $key->user_id($admin->id);
    $key->insert;

    say "done creating api key...";
}

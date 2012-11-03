sub {
    my $db = shift;
    use 5.12.0;
    say "adding admin";

    my $admin = $db->resultset('User')->new({});
    $admin->username('Admin');
    $admin->email('info@thegamecrafter.com');
    $admin->admin(1);
    $admin->encrypt_and_set_password('123qwe');
    $admin->insert;
}

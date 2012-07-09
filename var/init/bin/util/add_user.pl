#!/usr/bin/env perl

use lib '/data/[% project %]/lib', '/data/Wing/lib';


use Wing;
use Wing::Perl;
use Ouch;
use Getopt::Long;

my $username;
my $password;
my $admin = 0;

GetOptions(
    'username=s'    => \$username,
    'password=s'    => \$password,
    'admin'         => \$admin,
);

unless ($username) {
    say "usage: ./add_user.pl --username=Joe --password=123qwe --admin";
    exit;
}

eval {
    my $user = Wing->db->resultset('User')->new({});
    $user->username($username);
    $user->admin($admin),
    $user->encrypt_and_set_password($password);
    $user->insert;
};

if ($@) {
    say bleep;
}
else {
    say $username, ' created';
}


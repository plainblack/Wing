#!/usr/bin/env perl

BEGIN {
 die "Must set WING_HOME environment variable." unless $ENV{WING_HOME};
 die "Must set WING_APP environment variable." unless $ENV{WING_APP};
}
use lib $ENV{WING_APP}.'/lib', $ENV{WING_HOME}.'/lib';

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


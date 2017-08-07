#!/usr/bin/env perl

use lib $ENV{WING_APP}.'/lib', '/data/Wing/lib';

use Wing::Perl;
use Wing;

my $users = Wing->db->resultset('User')->search();

while (my $user = $users->next) {
    $user->username($user->username);
    $user->real_name($user->real_name);
    $user->email($user->email);
    $user->update;
}

say "Finished with users";

package Wing::Command::Command::user;

use Wing;
use Wing::Perl;
use Wing::Command -command;
use Ouch;

sub abstract { 'manage users' }

sub usage_desc { 'Add and modify user accounts.' }

sub opt_spec {
    return (
      [ 'add', 'add a new user' ],
      [ 'modify', 'change an existing user' ],
      [ 'list_admins', 'list all admin users' ],
      [ 'username=s', 'the user to modify' ],
      [ 'password=s', 'the password for the user' ],
      [ 'admin!', 'whether the user should be an admin' ],
    );
}

sub validate_args {
    my ($self, $opt, $args) = @_;
    # no args allowed but options!
    $self->usage_error("No args allowed, only options.") if @$args;
}

sub execute {
    my ($self, $opt, $args) = @_;
    my $users = Wing->db->resultset('User');
    if ($opt->{add}) {
        if (!$opt->{username}) {
            say "You must specify a username to add.";
            exit;
        }
        eval {
            my $user = $users->new({});
            $user->username($opt->{username});
            $user->admin($opt->{admin});
            $user->encrypt_and_set_password($opt->{password});
            $user->insert;
        };
        
        if ($@) {
            say bleep;
        }
        else {
            say $opt->{username}, ' created';
        }
    }
    elsif ($opt->{modify}) {
        if (!$opt->{username}) {
            say "You must specify a username to modify.";
            exit;
        }
        my $user = $users->search({username => $opt->{username}}, { rows => 1})->single;
        if (defined $user) {
            eval {
                $user->encrypt_and_set_password($opt->{password}) if exists $opt->{password};
                $user->admin($opt->{admin}) if exists $opt->{admin};
                $user->update;
            };
            
            if ($@) {
                say bleep;
            }
            else {
                say $opt->{username}, ' updated';
            }
        }
        else {
            say $opt->{username}, ' not found';
        }
    }
    elsif ($opt->{list_admins}) {
        my $admins = $users->search({admin => 1});
        while (my $user = $admins->next) {
            say $user->username;
        }
    }
    else {
        say "You must specify --add or --modify.";
    }
}

1;

=head1 NAME

wing user - Add and modify user accounts.

=head1 SYNOPSIS

 wing user --add --username=Joe --password=123qwe --admin

 wing user --modify --username=Joe --noadmin
 
=head1 DESCRIPTION

This provides simple user management. For all complex function, you should use the web interface. 

=head1 AUTHOR

Copyright 2012-2013 Plain Black Corporation.

=cut

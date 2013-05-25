package Wing::Command::Command::user;

use Wing;
use Wing::Perl;
use Wing::Command -command;
use Ouch;

sub abstract { 'manage users' }

sub usage_desc { 'Add and modify user accounts.' }

sub description {'Examples:
wing user --add=Joe --password=123qwe --admin

wing user --modify=Joe --noadmin --username=joseph

wing user --search=jo
'}

sub opt_spec {
    return (
      [ 'add=s', 'add a new user' ],
      [ 'modify=s', 'change an existing user' ],
      [ 'search=s', 'search users by keyword' ],
      [ 'list', 'list all users' ],
      [ 'list_admins', 'list all admin users' ],
      [ 'password=s', 'the password for the user' ],
      [ 'username=s', 'a new username for the user' ],
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
        eval {
            my $user = $users->new({});
            $user->username($opt->{add});
            $user->admin($opt->{admin});
            $user->encrypt_and_set_password($opt->{password});
            $user->insert;
        };
        
        if ($@) {
            say bleep;
        }
        else {
            say $opt->{add}, ' created';
        }
    }
    elsif ($opt->{modify}) {
        my $user = $users->search({username => $opt->{modify}}, { rows => 1})->single;
        if (defined $user) {
            eval {
                $user->encrypt_and_set_password($opt->{password}) if exists $opt->{password};
                $user->admin($opt->{admin}) if exists $opt->{admin};
                $user->username($opt->{username}) if exists $opt->{username};
                $user->update;
            };
            
            if ($@) {
                say bleep;
            }
            else {
                say $opt->{modify}, ' updated';
            }
        }
        else {
            say $opt->{modify}, ' not found';
        }
    }
    elsif ($opt->{search}) {
        my $list = $users->search({username => { like => '%'.$opt->{search}.'%'}});
        list_users($list);
    }
    elsif ($opt->{list}) {
        my $list = $users->search;
        list_users($list);
    }
    elsif ($opt->{list_admins}) {
        my $list = $users->search({admin => 1});
        list_users($list);
    }
    else {
        say "You must specify --add or --modify.";
    }
}


sub list_users {
    my $resultset = shift;
    my $users = $resultset->search(undef, {order_by => 'username'});
    while (my $user = $users->next) {
        my $suffix = '';
        if ($user->admin) {
            $suffix = ' (admin)';
        }
        say $user->username.$suffix;
    }
    say 'Total: ', $resultset->count;
}

1;

=head1 NAME

wing user - Add and modify user accounts.

=head1 SYNOPSIS

 wing user --add=Joe --password=123qwe --admin

 wing user --modify=Joe --noadmin --username=joseph

 wing user --search=jo
 
=head1 DESCRIPTION

This provides simple user management. For all complex function, you should use the web interface. 

=head1 AUTHOR

Copyright 2012-2013 Plain Black Corporation.

=cut

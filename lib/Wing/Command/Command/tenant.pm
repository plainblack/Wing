package Wing::Command::Command::tenant;

use Wing;
use Wing::Perl;
use Wing::Command -command;
use Ouch;

sub abstract { 'manage tenants' }

sub usage_desc { 'Add and delete tenant accounts' }

sub description {'Examples:
wing tenant --user=dude --add=dude

wing tenant --delete=dude

wing tenant --list
'}

sub opt_spec {
    return (
      [ 'user=s', 'assign a user to a newly added tenant' ],
      [ 'add=s', 'adds the specified tenant, requires --user' ],
      [ 'delete=s', 'deletes the specified tenant by name' ],
      [ 'list', 'list all tenant sites' ],
    );
}

sub validate_args {
    my ($self, $opt, $args) = @_;
    # no args allowed but options!
    $self->usage_error("No args allowed, only options.") if @$args;
}

sub execute {
    my ($self, $opt, $args) = @_;
    my $tenant_namespace = Wing->config->get('tenants/namespace');
    my $app = '/data/'.$tenant_namespace;
    my $lib = $app . '/lib';
    unshift @INC, $lib;
    my $db = Wing->db;
    if ($opt->{add}) {
        die "Must have a user when adding tenants" unless $opt->{user};
        my $owner = $db->resultset('User')->find({ username => $opt->{user}});
        die "Could not find your username: $opt->{user}" unless $owner;
        my $site = $db->resultset('Site')->new({});
        $site->name($opt->{add});
        $site->hostname($opt->{add});
        $site->shortname($opt->{add});
        $site->user($owner);
        say "Inserting a site named $opt->{add}";
        $site->insert();
        say "Created site named $opt->{add} owned by $opt->{user}";
        say "Database name".$site->database_name;
    }
    elsif ($opt->{delete}) {
        my $site = Wing->db->resultset('Site')->search({
            -or => [ { shortname => $opt->{delete}}, {hostname => $opt->{delete}}]
        })->single;
        if (! $site) {
            die "Could not find a tenant with name ".$opt->{delete};
        }
        say "Deleting $opt->{delete}";
        $site->delete;
    }
    elsif ($opt->{list}) {
        my $sites = Wing->db->resultset('Site')->search({});
        list_tenants($sites);
    }
    else {
        say "You must specify --add or --delete.";
    }
}

sub list_tenants {
    my $resultset = shift;
    my $tenants = $resultset->search(undef, {order_by => 'shortname'});
    while (my $tenant = $tenants->next) {
        say $tenant->shortname;
    }
    say 'Total: ', $resultset->count;
}


1;

=head1 NAME

wing tenant - Add and delete Wing tenant sites.

=head1 SYNOPSIS

 wing tenant --add=Joe --user=Joseph

 wing tenant --delete=Joe

 wing tenant --list

=head1 DESCRIPTION

This provides simple tenant management. For all complex function, you should use the web interface. 

=head1 AUTHOR

Copyright 2012-2013 Plain Black Corporation.

=cut

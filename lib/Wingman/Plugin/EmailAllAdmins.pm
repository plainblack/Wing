package Wingman::Plugin::EmailAllAdmins;

use Wing::Perl;
use Wing;

use Moose;
with 'Wingman::Role::Plugin', 'Wingman::Role::EmailRecovery';

=head1 NAME

Wingman::Plugin::EmailAllAdmins - Easily send an email to everyone that is an admin according to their user account.

=head1 SYNOPSIS

 Wingman->new->put('EmailAllAdmins', {
     template   => 'generic',
     params     => {
         subject    => 'Howdy',
         message    => 'This is a test.',
    },
   });

=head1 DESCRIPTION

This plugin uses the SendTemplatedEmail plugin to send a message to all admins. You can pass it any mkit template you like along with any template parameters that mkit needs. Just leave out the C<me> (aka C<User>) block in the template params and it will be filled in by this plugin.

=head1 METHODS

=head2 run ( job, args )

Confirm manual retention before delivery, then check deletion. See
L<Wingman::Role::EmailRecovery> for tube configuration and recovery.

=over

=item job

The L<Wingman::Job> you want to run.

=item args

A hash reference.

=over 

=item template

See L<Wing/send_templated_email> for details.

=item params

See L<Wing/send_templated_email> for details. Leave out the C<me> (aka C<User>) block.

=back

=back

=cut


sub run {
    my ($self, $job, $args) = @_;
    my $users = Wing->db->resultset('User')->search({admin => 1});
    while (my $user = $users->next) {
        my %params = %{$args->{params}};
        $params{me} = $user->describe(include_private => 1);
        Wing->send_templated_email(
            $args->{template},
            \%params,
            { wingman => 1 },
        );
    }
}

1;

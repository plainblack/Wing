package Wingman::Plugin::EmailAllUsers;

use Wing::Perl;
use Wing;

use Moose;
with 'Wingman::Role::Plugin';

=head1 NAME

Wingman::Plugin::EmailAllPrivilege - Easily send an email to every user that matches the C<query> criteria.

=head1 SYNOPSIS

 Wingman->new->put('EmailAllUsers', {
     template   => 'generic',
     query      => { staff_manager => 1},
     params     => {
         subject    => 'Howdy',
         message    => 'This is a test.',
     },
     options    => { priority => 5000, ttr => 600 }, # this could be slow and take a while, so lets implement it as such
   });

=head1 DESCRIPTION

This plugin uses the SendTemplatedEmail plugin to send a message to all users that match a user's C<query> criteria. You can pass it any mkit template you like along with any template parameters that mkit needs. Just leave out the C<me> (aka C<User>) block in the template params and it will be filled in by this plugin.

Keep in mind that due to the query you specify this could send thousands of emails, and it will not throttle the send, so make sure your outbound server can handle it. Also, this has no special bounce processing, so you'll need to take care of that yourself.

=head1 METHODS

=head2 run ( job, args )

Run this plugin then delete the job.

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

=item query

A L<DBIx::Class> query to limit the users list.

=back

=back

=cut


sub run {
    my ($self, $job, $args) = @_;
    my $users = Wing->db->resultset('User')->search($args->{query});
    while (my $user = $users->next) {
	if ($job->stats->time_left < 30) { # request more time if we have less than 30 seconds remaining to run
            $job->touch;
        }
        my %params = %{$args->{params}};
        $params{me} = $user->describe(include_private => 1);
	eval { 
		Wing->send_templated_email(
		    $args->{template},
		    \%params,
		);
	};
	if ($@) {
		Wing->log->error('Could not EmailAllUsers user '.$user->id.' because '.$@);
	}
    }
    $job->delete;
}

1;

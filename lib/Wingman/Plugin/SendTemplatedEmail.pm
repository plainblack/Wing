package Wingman::Plugin::SendTemplatedEmail;

use Wing::Perl;
use Wing;
use Ouch;

use Moose;
with 'Wingman::Role::Plugin';

=head1 NAME

Wingman::Plugin::SendTemplatedEmail - A background email sender.

=head1 SYNOPSIS

 Wing->send_templated_email($template, $params, { wingman => 1 });

=head1 DESCRIPTION

This plugin allows you to send email via L<Wingman> rather than having that process tie up a web process in the foreground. Just add C<wingman=1> to L<Wingman/send_templated_email> as an option.

B<NOTE:> There is a generic mkit template included with wing called C<generic> that will be installed in C<var/mkits>. You can easily use this to send unformatted messages, but in general you should create templated messages for all your correspondence. 

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

See L<Wing/send_templated_email> for details.

=item options

See L<Wing/send_templated_email> for details.

=back

=back

=cut


sub run {
    my ($self, $job, $args) = @_;
    eval {
        Wing->send_templated_email(
            $args->{template},
            $args->{params},
            $args->{options},
        );
    };
    if (kiss 442) { ##bad address
        Wing->log->warn("Could not send templated email to user: $@");
    }
    elsif (hug) {
        Wing->log->error($@);
    }

    $job->delete;
}

1;

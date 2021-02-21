package Wingman::Plugin::PostWebHook;

use Wing::Perl;
use Wing;

use Moose;
with 'Wingman::Role::Plugin';

=head1 NAME

Wingman::Plugin::PostWebHook - Tries to repeatedly post to a web hook over time.

=head1 SYNOPSIS

 Wingman->new->put('PostWebHook', {
     id   => 'xxx',
     payload     => {...},
   });

=head1 DESCRIPTION

This plugin expects an app to have a class called 'WebHook' which is generated from L<Wing::Role::Result::WebHook>. It will then call the C<post> method on that repeatedly until success. If it fails, it will try again after a progressively longer wait. It will send an email to the owner of the web hook after 5 failures. If it fails after trying and failing 100 times it will cancel the subscription.

=head1 METHODS

=head2 run ( job, args )

Run this plugin then delete the job.

=over

=item job

The L<Wingman::Job> you want to run.

=item args

A hash reference.

=over 

=item id

The C<i> of a C<WebHook>.

=item payload

A hashref containing the content to be sent to the webhook.

=back

=back

=cut


sub run {
    my ($self, $job, $args) = @_;
    my $notify_after = 5;
    my $stop_retry_after = 100;
    my $unsubscribe_after = 1000;
    my $hook = Wing->db->resultset('WebHook')->find($args->{id});
    if (defined $hook) {
        unless ($hook->post($args->{payload})) {
            if ($hook->failures_since_last_success >= $unsubscribe_after) {
                $hook->delete;
            }
            elsif ($hook->failures_since_last_success <= $stop_retry_after) {
                Wingman->new->put('PostWebHook', {
                    id      => $hook->id,
                    payload => $args->{payload},
                }, { 
                    priority    => 5000, 
                    ttr         => 60, 
                    delay       => 3600 * $hook->failures_since_last_success,
                });
                if ($hook->failures_since_last_success == $notify_after) {
                    $hook->notify_about_failures($args->{payload}, $notify_after, $stop_retry_after, $unsubscribe_after);
                }
            }
        }
    }
    else {
        Wing->log->error('Could not find web hook '.$args->{id});
    }
    $job->delete;
}

1;

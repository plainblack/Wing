package Wingman::Plugin::TriggerWebHook;

use Wing::Perl;
use Wing;

use Moose;
with 'Wingman::Role::Plugin';
use Wingman;

=head1 NAME

Wingman::Plugin::TriggerWebHook - Search for subscribers to a webhook and initiate posts to subscribers.

=head1 SYNOPSIS

 Wingman->new->put('TriggerWebHook', {
     owner_class   => 'User',
     owner_id   => 'xxx',
     event   => 'DidAThing',
     payload     => {...},
   }, { ttr => 300, priority => 5000 });

=head1 DESCRIPTION

This plugin expects an app to have a class called 'WebHook' which is generated from L<Wing::Role::Result::WebHook>. It will search the webhooks for subscribers matching the C<owner_class>, C<owner_id>, and C<event>, and when it finds one, it will initiate L<Wingman::Plugin::PostWebHook>.

=head1 METHODS

=head2 run ( job, args )

Run this plugin then delete the job.

=over

=item job

The L<Wingman::Job> you want to run.

=item args

A hash reference.

=over 

=item owner_class

An owner_class name in your app. Such as C<User>. 

=item owner_id

The C<id> of an instance of C<owner_class>.

=item event

The name of an event defined by your app.

=item payload

A hashref containing the content to be sent to the webhook.

=back

=back

=cut


sub run {
    my ($self, $job, $args) = @_;
    my $hooks = Wing->db->resultset('WebHook')->search({owner_class => $args->{owner_class}, owner_id => $args->{owner_id}, event => $args->{event}});
    while (my $hook = $hooks->next) {
        if ($job->stats->time_left < 30) { # request more time if we have less than 30 seconds remaining to run
            $job->touch;
        }
        Wingman->new->put('PostWebHook', {
            id   => $hook->id,
            payload     => $args->{payload},
        });
    }
    $job->delete;
}

1;

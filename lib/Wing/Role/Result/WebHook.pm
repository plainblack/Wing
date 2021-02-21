package Wing::Role::Result::WebHook;

use Wing::Perl;
use Ouch;
use Moose::Role;
with 'Wing::Role::Result::Field';
with 'Wing::Role::Result::UserControlled';
use LWP::UserAgent;
use JSON qw/to_json/;
use Crypt::Mac::HMAC qw( hmac_hex );

=head1 NAME

Wing::Role::Result::WebHook - An asynchronous REST callback system for Wing. 

=head1 SYNOPSIS

 with 'Wing::Role::Result::WebHook';

=head1 DESCRIPTION

This is a foundational role for the required WebHook class. WebHooks are used to make asynchronous callbacks to subscribers.

=head1 REQUIREMENTS

All Wing Apps can have a class called AppName::DB::Result::WebHook that uses this role as a starting point.

=head1 ADDS

=head2 Fields

=over

=item owner_class 

The wing class that has the hook event attached it it.

=item owner_id

The id of an instance of the class. Note that the user that subscribes to this webhook must have C<can_edit> privilege for this object instance.

=item event

The name of the event that the user is subscribing to on this object.

=item callback_uri

A POST will be made to this URI each time this event is triggered.

=item success_count

The number of times a C<200> was the result of posting to the callback_uri.

=item error_count

The number of times anything other than C<200> was the result of posting to the callback_uri.

=item last_status_code

The most recent HTTP status code returned from the POST.

=item failures_since_last_success

The number of failed attempts since the last successful post was made.

=back

=head2 Parents

=over

=item apikey

A relationship to a L<Wing::Role::Result::APIKey> enabled object.

=back

=cut

before wing_finalize_class => sub {
    my ($class) = @_;
    $class->wing_fields(
        owner_class    => {
            dbic    => { data_type => 'varchar', size => 60, is_nullable => 0 },
            view    => 'public',
            edit    => 'required',
        },
        owner_id                     => {
            dbic    => { data_type => 'char', size => 36, is_nullable => 0 },
            view    => 'private',
            edit    => 'required',
        },
        event                     => {
            dbic    => { data_type => 'varchar', size => 60, is_nullable => 0 },
            view    => 'private',
            edit    => 'required',
        },
        callback_uri                 => {
            dbic    => { data_type => 'varchar', size => 255, is_nullable => 0 },
            view    => 'private',
            edit    => 'required',
        },
        success_count             => {
            dbic    => { data_type => 'bigint', is_nullable => 0, default_value => 0 },
            view    => 'private',
        },
        error_count             => {
            dbic    => { data_type => 'bigint', is_nullable => 0, default_value => 0 },
            view    => 'private',
        },
        last_status_code             => {
            dbic    => { data_type => 'int', is_nullable => 0, default_value => 200 },
            view    => 'private',
        },
        failures_since_last_success             => {
            dbic    => { data_type => 'int', is_nullable => 0, default_value => 0 },
            view    => 'private',
        },
    );
};

with 'Wing::Role::Result::Parent';

before wing_finalize_class => sub {
    my ($class) = @_;
    my $namespace = $class;
    $namespace =~ s/^(\w+)\:.*$/$1/;
    $class->wing_parent(
        apikey   => {
            view                => 'public',
            edit                => 'required',
            related_class       => $namespace.'::DB::Result::APIKey',
            related_id          => 'api_key_id',
        }
    );
};

around describe => sub {
    my ($orig, $self, %options) = @_;
    my $out = $orig->($self, %options);
    return $out;
};

after insert => sub {
    my $self = shift;
    $self->post({}, 'subscribe');
};

before delete => sub {
    my $self = shift;
    $self->post({}, 'unsubscribe');
};

sub test {
    my ($self, $payload) = @_;
    $payload //= {};
    $self->post($payload, 'test');
}

sub post {
    my ($self, $payload, $type) = @_;
    $type //= 'data';
    my $message = {
        type => $type,
        payload => $payload,
        owner_id => $self->owner_id,
        owner_class => $self->owner_class,
        event => $self->event,
        id => $self->id,
    };
    my $response;
    eval {
        my $json = to_json($message);
        my $timestamp = time();
        my $hmac = hmac_hex('SHA256', $self->apikey->private_key, $timestamp.'.'.$json);
        my $ua = LWP::UserAgent->new;
        $ua->timeout(10);
        $response = $ua->post(
            $self->callback_uri,
            [
                epoch => $timestamp,
                hmac => $hmac,
                message => $json,
            ],
        );
    };
    if ($@) {
        $self->last_status_code(999);
        Wing->log->error('Could not post to webhook '.$self->id.' because: '.$@);
    }
    elsif ($response && $response->is_success) {
        $self->success_count($self->success_count+1);
        $self->failures_since_last_success(0);
        $self->last_status_code($response->code);
        $self->update;
        return 1;
    }
    elsif ($response) {
        $self->last_status_code($response->code);
    }
    else {
        $self->last_status_code(998);
        Wing->log->error('Could not post to webhook '.$self->id.' because we did not get a response object, probably URL related.');
    }
    $self->error_count($self->error_count+1);
    $self->failures_since_last_success($self->failures_since_last_success+1);
    $self->update;
    return 0;
}

sub notify_about_failures {
    my ($self, $payload, $notify_after, $stop_retry_after, $unsubscribe_after) = @_;
    eval { 
        $self->user->send_templated_email('generic',{
            subject => 'Web hook failing',
            message => 'Your web hook with id '.$self->id.' is failing to post to '.$self->callback_uri." after $notify_after attempts. If it is still failing after $stop_retry_after attempts we will not retry failed attempts. If it is still failing after $unsubscribe_after attempts this web hook will automatically unsubscribe. The payload for this most recent attempt is as follows: \n\n".to_json($payload),
        });
    };
    if ($@) {
        Wing->log->error('Could not send webhook '.$self->id.' failure notification, because: '.$@);
    }
}


1;

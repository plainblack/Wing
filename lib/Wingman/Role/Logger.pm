package Wingman::Role::Logger;

=head1 NAME

Wingman::Role::Logger - A role that exposes some nice logging methods for Wingman's internal functions.

=head1 DESCRIPTION

There is no reason for you to use this in your own modules.

=cut

use Moose::Role;

sub _log {
    my ($self, $method, $job, $message) = @_;
    my $job_params = ($job->can('data')) ? $job->data : $job->beanstalk_job->data;
    Wing->log->$method(sprintf('Wingman: %s // %s', $message, $job_params));
}

sub log_info {
    my $self = shift;
    $self->_log('info', @_);
}

sub log_fatal {
    my $self = shift;
    $self->_log('fatal', @_);
}

sub log_debug {
    my $self = shift;
    $self->_log('debug', @_);
}

sub log_warn {
    my $self = shift;
    $self->_log('warn', @_);
}

sub log_trace {
    my $self = shift;
    $self->_log('trace', @_);
}

sub log_error {
    my $self = shift;
    $self->_log('error', @_);
}




1;

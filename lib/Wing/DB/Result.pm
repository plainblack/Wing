package Wing::DB::Result;

use Wing::Perl;
use DateTime;
use Ouch;
use List::MoreUtils qw(any);
use Moose;
use MooseX::NonMoose;
extends 'DBIx::Class::Core';

=head1 NAME

Wing::DB::Result - The kernel of every object in Wing.

=head1 SYNOPSIS

 extends 'Wing::DB::Result';

=cut

__PACKAGE__->load_components('UUIDColumns', 'TimeStamp', 'InflateColumn::DateTime', 'InflateColumn::Serializer', 'Core');

=head1 METHODS

=head2 wing_apply_relationships()

Power user feature.

=cut

sub wing_apply_relationships {}

=head2 wing_apply_fields()

Power user feature.

=cut

sub wing_apply_fields {
    my $class = shift;
    $class->add_columns(
        id                      => { data_type => 'char', size => 36, is_nullable => 0 },
        date_created            => { data_type => 'datetime', set_on_create => 1 },
        date_updated            => { data_type => 'datetime', set_on_create => 1, set_on_update => 1 },
    );
    $class->set_primary_key('id');
    $class->uuid_columns('id');
}

=head2 wing_finalize_class(options)

Call this this method once you have defined all fields and relationships in your object.

=over

=item options

A hash.

=over

=item table_name

The name of the table that should be generated for this object type.

=back

=back

=cut

sub wing_finalize_class {
    my ($class, %options) = @_;
    $class->table($options{table_name});
    $class->uuid_class('::Data::GUID');
    $class->wing_apply_fields;
    $class->wing_apply_relationships;
}

=head2 BUILD()

Constructor. No parameters.

=cut


sub BUILD {
    my $self = shift;
    unless (defined $self->id) {
        $self->id(Data::GUID->new->as_string);
    }
    foreach my $col ($self->result_source->columns) {
        my $default = $self->result_source->column_info($col)->{default_value};
        $self->set_column($col => $default) if (defined $default && !defined $self->$col());
    }
    return $self;
}

=head2 wing_object_class()

Returns the class name of the object, without the parent package path.

=cut

sub wing_object_class {
    my $self = shift;
    my $class = ref $self || $self;
    $class =~ s/^.*:(\w+)$/$1/;
    return $class;
}

=head2 wing_object_name()

Defaultly returns the same as C<wing_object_class> but should be overrriden to return a human friendly name for the object.

=cut

sub wing_object_name {
    my $self = shift;
    return $self->wing_object_class;
}

=head2 wing_object_type()

Returns a lower case version of C<wing_object_class>. Used for addressing objects in URLs.

=cut

sub wing_object_type {
    my $self = shift;
    return lc($self->wing_object_class);
}

=head2 wing_object_api_uri()

Returns the RESTful web service API URI for this object. If you do a GET request on this URI you'd fetch the object's public data.

=cut

sub wing_object_api_uri {
    my $self = shift;
    return '/api/'.$self->wing_object_type.'/'.$self->id;
}

=head2 describe(options)

Serializes important data about the object and returns it as a hash reference.

B<NOTE:> This method is modal. It will return different data depending on the information passed to it via the C<options> hash.

=over

=item options

A hash.

=over

=item include_options

A boolean that indicates whether the describe output should include the result of the C<field_options> method.

=item include_private

A boolean that indicates whether the describe method should include sensitive data that only the owner of the object normally has access to.

=item include_admin

A boolean that indicates whether the describe method should include sensitive data that only admins normally have access to.

=item include_relationships

A boolean that inicates whether the describe method should include API links to this object's relationships.

=item current_user

A reference to a user object. If this is included then the object can determine whether to display private data on it's own.

=back

=back

=over

=item Returns

Unless overridden in a child or consumer class, all Wing objects will have these fields being
returned by describe.

=over

=item id

=item object_type

=item object_name

=item date_updated

=item date_created

=back

=back

=cut

sub describe {
    my ($self, %options) = @_;
    my $out = {
        id          => $self->id,
        object_type => $self->wing_object_type,
        object_name => $self->wing_object_name,
        date_updated=> Wing->to_mysql($self->date_updated),
        date_created=> Wing->to_mysql($self->date_created),
    };
    if (defined $options{current_user} && $options{include_private}) {
        $out->{can_view} = (eval { $self->can_view($options{current_user}) }) ? 1 : 0;
        $out->{can_edit} = (eval { $self->can_edit($options{current_user}) }) ? 1 : 0;
    }
   if ($options{include_options}) {
        $out->{_options} = $self->field_options(%options);
    }
    if ($options{include_relationships}) {
        $out->{_relationships}{self} = $self->wing_object_api_uri;
    }
    return $out;
}

=head2 describe_delete ()

Returns:

 { success => 1 }

But sometimes you may want to add other info to the response after the delete. Wrapping this method will allow you to do so.

=cut

sub describe_delete {
    return { success => 1 };
}

=head2 field_options( options )

Returns options for each field. Is wrapped by roles like L<Wing::Role::Result::Field> to expose enumerated options that some fields require.

=over

=item options

Same options as the c<describe> method.

=back

=cut

sub field_options {
    return {};
}

=head2 touch()

Updates the C<date_updated> field in the object to the current date.

=cut

sub touch {
    my $self = shift;
    if ($self->in_storage) {
        $self->update({date_updated => DateTime->now});
    }
}

=head2 sql_deploy_hook(sqlt_table)

Is wrapped by roles like L<Wing::Role::Result::Field> to add special table indexes and other SQL deployment oddities.

=cut

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;
    $sqlt_table->add_index(name => 'idx_date_created', fields => ['date_created']);
    $sqlt_table->add_index(name => 'idx_date_updated', fields => ['date_updated']);
    $sqlt_table->extra(mysql_collate => 'utf8_unicode_ci');
    $sqlt_table->extra(mysql_charset => 'utf8');
}

=head2 public_params()

Is wrapped by roles like L<Wing::Role::Result::Field> to expose whether a Wing object's parameters should be viewable publicly.

=cut

sub public_params {
    return [qw(id object_type object_name date_updated date_created)];
}

=head2 private_params()

Is wrapped by roles like L<Wing::Role::Result::Field> to expose whether a Wing object's parameters should be viewable by the object's controller.

=cut

sub private_params {
    return [];
}

=head2 admin_viewable_params()

Is wrapped by roles like L<Wing::Role::Result::Field> to expose whether a Wing object's parameters should be viewable by admins.

=cut

sub admin_viewable_params {
    return [];
}

=head2 postable_params()

Is wrapped by roles like L<Wing::Role::Result::Field> to expose whether a Wing object's parameters should be postable.

=cut

sub postable_params {
    return [];
}

=head2 required_params()

Is wrapped by roles like L<Wing::Role::Result::Field> to not allow an object instance to be created unless it includes these fields.

=cut

sub required_params {
    return [];
}

=head2 privileged_params()

Is wrapped by roles like L<Wing::Role::Result::Field> to not allow an object instance to updated unless that field passes its privilege check.

=cut

sub privileged_params {
    return {};
}

=head2 postable_params_by_priority()

Is wrapped by roles like L<Wing::Role::Result::Field> to build a list of all parameters that can be posted, in order of priority so they're processed in the correct order.

=cut

sub postable_params_by_priority {
    return [];
}

=head2 get_postable_params_by_priority()

Get the list of params that can be posted, by name

=cut

sub get_postable_params_by_priority {
    my ($self) = @_;
    my $params = $self->postable_params_by_priority;
    my @params = map { $_->[0] }
                 sort { $a->[1] <=> $b->[1] }
                 @{ $params }
                 ;
    return @params;
}

=head2 admin_postable_params()

Is wrapped by roles like L<Wing::Role::Result::Field> to only allow this field to be postable by admin users.

=cut

sub admin_postable_params {
    return [];
}

=head2 relationship_accessors()

Is wrapped by roles like L<Wing::Role::Result::Parent>, L<Wing::Role::Result::Child>, and L<Wing::Role::Result::Cousin> to return an array reference of accessor names for relationships of this object. This is then used to automatically generate relationships in L<Wing::Rest>.

=cut

sub relationship_accessors {
    return [];
}

=head2 can_edit(user)

Can this user edit this object? By default C<is_admin> in L<Wing::Role::Result::User> can edit the object. All other privileges must be added. L<Ouch>es C<450> if the privileges are not sufficient.

=over

=item user

A reference to a user object.

=back

=cut

sub can_edit {
    my ($self, $user) = @_;
    return 1 if defined $user && $user->is_admin;
    my $message;
    if (defined $user) {
        $message = $user->display_name.' has i';
    }
    else {
        $message = 'I';
    }
    $message .= 'nsufficient privileges for '.$self->wing_object_name.'.';
    ouch(450,$message);
}

=head2 can_link_to($user)

Can this user link to this object?  By default, if you C<can_edit> then you can link to it with the L<Wing::Role::Result::Parent> role.

=over

=item user

A reference to a user object.

=back

=cut

sub can_link_to {
    my $self = shift;
    return $self->can_edit(@_);
}

=head2 can_view(user)

Can this user view this object?  By default, if you C<can_edit> then you can view it.

=over

=item user

A reference to a user object.

=back

=cut

sub can_view {
    my $self = shift;
    return $self->can_edit(@_);
}

=head2 can_delete(user)

Can this user delete this object? By default if you C<can_edit> an object you can delete it.

=over

=item user

A reference to a user object.

=back

=cut

sub can_delete {
    my $self = shift;
    return $self->can_edit(@_);
}

=head2 verify_creation_params(params, current_user)

Used by web/rest interfaces to validate posted parameters for creation. Throws a 441 ouch if a required parameter is not present.

=over

=item params

A hash reference of parameters to verify.

=item current_user

A reference to the current user object.

=back

=cut

sub verify_creation_params {
    my ($self, $params, $current_user) = @_;
    foreach my $param (@{$self->required_params}) {
        my $value = $params->{$param} || $self->$param;
        ouch(441, $param.' is required.', $param) unless defined $value && $value ne '';
    }
}

=head2 verify_posted_params(params, current_user, tracer)

Used by web/rest interfaces to validate posted parameters for update. Throws a 441 ouch if a required parameter is not present.  Otherwise, it updates the object with the parameters.

=over

=item params

A hash reference of parameters to verify.

=item current_user

A reference to the current user object.

=item tracer

See L<Wing::Rest> C<get_tracer()>

=back

=cut

sub verify_posted_params {
    my ($self, $params, $current_user, $tracer) = @_;
    my $is_admin = defined $current_user && $current_user->is_admin;
    my $can_edit = eval { $is_admin || $self->can_edit($current_user, $tracer) };
    my $cant_edit = $@;
    my $required_params = $self->required_params;
    my $privileged_params = $self->privileged_params;
    my $admin_postable_params = $self->admin_postable_params;
    my @postable_params = $self->get_postable_params_by_priority;
    PARAM: foreach my $param (@postable_params) {
        if (exists $params->{$param}) {
            my $saveit = sub {
                $self->$param($params->{$param});
            };

            if (any {$_ eq $param} @$required_params && $params->{$param} eq '') {
                ouch(441, $param.' is required.', $param) unless $params->{$param};
            }

            # admins can save whatever they want
            if ($is_admin) {
                $saveit->();
                next PARAM;
            }

            # skip admin postable params unless they are a privileged param
            my $is_admin_postable = any {$_ eq $param} @{$admin_postable_params};
            if ($is_admin_postable) {
                next PARAM unless exists $privileged_params->{$param};
            }

            # if it's a privileged param and it can pass the privilege check, save it
            if (exists $privileged_params->{$param}) {
                if ($self->check_privilege_method($privileged_params->{$param}, $current_user)) {
                    $saveit->();
                    next PARAM;
                }
                elsif ($is_admin_postable) { # if we weren't allowed to edit and it was admin postable we need to skip it
                    next PARAM;
                }
            }

            # if we are allowed to edit it then save it
            if ($can_edit) {
                $saveit->();
                next PARAM;
            }

            # everything failed
            ouch 450, $cant_edit, $param;
        }
    }
}

=head2 duplicate([handler])

Duplicates this object with a new id. Can be extended to duplicate auxillary data.

=over

=item handler

Optional. A subroutine reference that will be passed the original object and the copy so that the duplicate can be manipulated before any copying of data begins.

=back

=cut

sub duplicate {
    my ($self, $handler) = @_;
    my $copy = $self->result_source->schema->resultset(ref $self)->new({});
    if (defined $handler && ref $handler eq 'CODE') {
	$handler->($self, $copy);
    }
    return $copy;
}

=head2 check_privilege_method( method, current_user )

Executes a method while passing it the current user object to check for privileges on a field. This is used by the L<Wing::Role::Result::Field> role.

=over

=item method

The name of the method on this object to execute.

=item current_user

A C<MyApp::DB::Result::User> object.

=back

=cut

sub check_privilege_method {
    my ($self, $method, $current_user) = @_;
    return 0 unless defined $method;
    return 0 unless defined $current_user;
    my $result = eval { $self->$method($current_user) };
    if ($@) {
        Wing->log->debug($method.' on '.$self->wing_object_name.' failed privilege check with '.$@);
        return 0;
    }
    return $result ? 1 : 0;
}

=head2 SEE ALSO

L<Ouch>, L<DBIx::Class>

=cut

1;

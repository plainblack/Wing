package Wing::DB::Result;

use Wing::Perl;
use DateTime;
use Ouch;
use base 'DBIx::Class::Core';

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

=head2 new()

Constructor. No parameters.

=cut

# override default DBIx::Class constructor to set defaults from schema
sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    foreach my $col ($self->result_source->columns) {
        my $default = $self->result_source->column_info($col)->{default_value};
        $self->$col($default) if (defined $default && !defined $self->$col());
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
        $out->{_options} = $self->field_options;
    }
    if ($options{include_relationships}) {
        $out->{_relationships}{self} = $self->wing_object_api_uri;
    }
    return $out;
}

=head2 field_options()

Returns options for each field. Is wrapped by roles like L<Wing::Role::Result::Field> to expose enumerated options that some fields require.

=cut

sub field_options {
    return {};
}

=head2 touch()

Updates the C<date_updated> field in the object to the current date.

=cut

sub touch {
    my $self = shift;
    $self->update({date_updated => DateTime->now});
}

=head2 sql_deploy_hook(sqlt_table)

Is wrapped by roles like L<Wing::Role::Result::Field> to add special table indexes and other SQL deployment oddities.

=cut

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;
    $sqlt_table->add_index(name => 'idx_date_created', fields => ['date_created']);
    $sqlt_table->add_index(name => 'idx_date_updated', fields => ['date_updated']);
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

=head2 admin_postable_params()

Is wrapped by roles like L<Wing::Role::Result::Field> to only allow this field to be postable by admin users.

=cut

sub admin_postable_params {
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
    ouch(450, 'Insufficient privileges.');
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
        ouch(441, $param.' is required.', $param) unless $params->{$param} || $self->$param;
    }
}

=head2 verify_posted_params(params, current_user)

Used by web/rest interfaces to validate posted parameters for update. Throws a 441 ouch if a required parameter is not present.  Otherwise, it updates the object with the parameters.

=over

=item params

A hash reference of parameters to verify.

=item current_user

A reference to the current user object.

=back

=cut

sub verify_posted_params {
    my ($self, $params, $current_user) = @_;
    my $required_params = $self->required_params;
    if (defined $current_user && $current_user->is_admin) {
        foreach my $param (@{$self->admin_postable_params}) {
            if (exists $params->{$param}) {
                if ($param ~~ $required_params && $params->{$param} eq '') {
                    ouch(441, $param.' is required.', $param) unless $params->{$param};
                }
                $self->$param($params->{$param});
            }
        }
    }
    foreach my $param (@{$self->postable_params}) {
        if (exists $params->{$param}) {
            if ($param ~~ $required_params && $params->{$param} eq '') {
                ouch(441, $param.' is required.', $param) unless $params->{$param};
            }
            $self->$param($params->{$param});
        }
    }
}

=head2 duplicate()

Duplicates this object with a new id. Can be extended to duplicate auxillary data.

=cut

sub duplicate {
    my ($self) = @_;
    return $self->result_source->schema->resultset(ref $self)->new({});
}

=head2 SEE ALSO

L<Ouch>, L<DBIx::Class>

=cut

1;

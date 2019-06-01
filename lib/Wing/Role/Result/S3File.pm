package Wing::Role::Result::S3File;

use Moose::Role;
use Wing::Perl;
use Ouch;
use Imager;
use Image::ExifTool;
use Net::Amazon::S3;
use DateTime::Format::HTTP;
use File::Temp qw(tempfile);

with 'Wing::Role::Result::Field';

requires 's3_bucket_name';
requires 'file_relationship_name';
requires 'local_cache_path';

before wing_finalize_class => sub {
    my ($class) = @_;
    $class->wing_fields(
        metadata => {
            dbic    => { data_type => 'mediumblob', is_nullable => 1, 'serializer_class' => 'JSON', 'serializer_options' => { utf8 => 1 }  },
            view    => 'private',
        },
        filename => {
            dbic 	=> { data_type => 'varchar', size => 255, is_nullable => 0 },
            view	=> 'public',
        },
    );
};

sub file_relationship_id {
    my $self = shift;
    my $method = $self->file_relationship_name.'_id';
    return $self->$method(@_);
}

sub file_uri {
    my $self = shift;
    return '//s3.amazonaws.com/'.Wing->config->get('aws/'.$self->s3_bucket_name).'/'.$self->file_relationship_id.'/'.$self->id.'/'.$self->filename;
}

before delete => sub {
    my $self = shift;
    my $s3 = $self->s3;
    my $bucket = $s3->bucket(Wing->config->get('aws/'.$self->s3_bucket_name));
    $bucket->delete_key($self->file_relationship_id.'/'.$self->id.'/thumbnail'.$self->extension) or die $s3->err . ": " . $s3->errstr;
};

sub file_size {
    my $self = shift;
    my $size = $self->metadata->{FileSize};
    $size =~ m/^(\d+)\s*(\w+)$/;
    my $value = $1;
    my $units = $2;
    my $multiplier = 1;
    if ($units eq 'MB') {
        $multiplier = 1024 * 1024;
    }
    elsif ($units eq 'kB') {
        $multiplier = 1024;
    }
    return $value * $multiplier;
}

sub file_type {
    my $self = shift;
    return $self->metadata->{FileType};
}

sub extension {
    my $self = shift;
    my $type = lc($self->file_type);
    return '.' . $type;
}

sub initialize {
    my ($class, $related_id, $filename, $path) = @_;
    my $log = Wing->log;
    $log->info('Trying to handle upload for '.$path);
    my $self = Wing->db->resultset($class)->new({});
    $self->id(Data::GUID->new->as_string); # want the id and haven't inserted yet
    $self->file_relationship_id($related_id);
    $self->filename($self->fix_filename($filename));
    my $info = Image::ExifTool::ImageInfo($path, [], { Exclude => ['FileName','Directory','FilePermissions']});
    my $meta;
    while ( my ($key, $value) = each %{$info}) {
        next if ref $value;
        $meta->{$key} = $value;
    }
    $self->metadata($meta);
    $self->upload_file_to_s3($path, $self->filename);
    $self->insert;
    return $self;
}

sub fix_filename {
    my ($self, $filename) = @_;
    $filename =~ s/[^a-z0-9\_\.\-]/-/ximg;
    return $filename;
}

has s3 => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        my $config = Wing->config;
        return Net::Amazon::S3->new(
            aws_access_key_id     => $config->get('aws/access_key'), 
            aws_secret_access_key => $config->get('aws/secret_key'),
            retry                 => 1,
            use_virtual_host      => 0,
        );
    },
);

sub upload_file_to_s3 {
    my ($self, $path, $filename) = @_;
    my $config = Wing->config;
    my %types = (
        PDF     => "application/pdf",
        DOC     => "application/msword",
        DOCX    => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        ODT     => "application/vnd.oasis.opendocument.text",
    );
    my $type = $types{$self->file_type} || 'application/octet-stream';
    my $s3 = $self->s3;
    my $bucket = $s3->bucket($config->get('aws/'.$self->s3_bucket_name));
    my $log = Wing->log;
    $log->info('Uploading file '.$path.' to S3.');
    my $success = eval { $bucket->add_key_filename(
        $self->file_relationship_id.'/'.$self->id.'/'.$filename,
        $path,
        {
            'Content-Type'  => $type,
            'Expires'       => DateTime::Format::HTTP->format_datetime(DateTime->now->add(years=>5)),
            'Cache-Control' => 'max-age=290304000, public', 
            acl_short       => 'public-read',
        }
    ) };
    if ($@) {
        $log->error("Failed uploading $path because: ".$@);
    }
    elsif ($success) {
        return $self;
    }
    else {
        $log->error($s3->err . ": " . $s3->errstr);
    }
    ouch 504, 'Could not connect to file storage system.';
}

around describe => sub {
    my ($orig, $self, %options) = @_;
    my $out = $orig->($self, %options);
    $out->{file_uri} = $self->file_uri;
    if ($options{include_related_objects}) {
        $out->{metadata} = $self->metadata;
    }
    return $out;
};

sub fetch {
    my $self = shift;
    my $uri = $self->file_uri;
    my $filename = $self->filename;
    my $path = $self->local_cache_path . '/'.$self->id.'/' . $filename;
    unless (-f $path) {
        Wing->log->info('Fetching '.$filename.' from S3');
        my $command = '/usr/bin/curl -S -o '.$path.' --retry 3 --create-dirs --url http:'.$uri;
        Wing->log->debug($command);
        unless (system($command) == 0) {# download with curl so not to eat up too much ram in this process
            Wing->log->error('Could not retrieve file '.$filename.' from S3: '.$!);
            ouch 504, 'Could not retrieve file '.$filename.' from S3: '.$!;
        }
    }
    return $path;
}

1;

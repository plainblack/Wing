package Wing::Role::Result::S3Image;

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
requires 'image_relationship_name';
requires 'max_image_size';
requires 'thumbnail_size';

before wing_finalize_class => sub {
    my ($class) = @_;
    $class->wing_fields(
        metadata => {
            dbic    => { data_type => 'mediumblob', is_nullable => 1, 'serializer_class' => 'JSON' },
            view    => 'private',
        },
        filename => {
            dbic 	=> { data_type => 'varchar', size => 60, is_nullable => 0 },
            view	=> 'public',
        },
    );
};

sub image_relationship_id {
    my $self = shift;
    my $method = $self->image_relationship_name.'_id';
    return $self->$method(@_);
}

sub image_uri {
    my $self = shift;
    return '//s3.amazonaws.com/'.Wing->config->get('aws/'.$self->s3_bucket_name).'/'.$self->image_relationship_id.'/'.$self->id.'/'.$self->filename;
}

sub thumbnail_uri {
    my $self = shift;
    return '//s3.amazonaws.com/'.Wing->config->get('aws/'.$self->s3_bucket_name).'/'.$self->image_relationship_id.'/'.$self->id.'/thumbnail'.$self->extension;
}

before delete => sub {
    my $self = shift;
    my $s3 = $self->s3;
    my $bucket = $s3->bucket(Wing->config->get('aws/'.$self->s3_bucket_name));
    $bucket->delete_key($self->image_relationship_id.'/'.$self->id.'/'.$self->filename) or die $s3->err . ": " . $s3->errstr;
    $bucket->delete_key($self->image_relationship_id.'/'.$self->id.'/thumbnail'.$self->extension) or die $s3->err . ": " . $s3->errstr;
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
    $type = 'jpg' if $type eq 'jpeg';
    return '.' . $type;
}

sub initialize {
    my ($class, $related_id, $filename, $path) = @_;
    my $log = Wing->log;
    $log->info('Trying to handle upload for '.$path);
    my $self = Wing->db->resultset($class)->new({});
    $self->id(Data::GUID->new->as_string); # want the id and haven't inserted yet
    $self->image_relationship_id($related_id);
    $self->filename($self->fix_filename($filename));
    $self->resize_image($path);
    my $info = Image::ExifTool::ImageInfo($path, [], { Exclude => ['FileName','Directory','FilePermissions']});
    my $meta;
    while ( my ($key, $value) = each %{$info}) {
        next if ref $value;
        $meta->{$key} = $value;
    }
    $self->metadata($meta);
    unless ($meta->{FileType} ~~ ['JPEG','PNG']) {
        ouch 442, 'File must be a .jpg or .png.';
    }
    my $thumbnail = $self->generate_thumbnail($path);
    $self->upload_file_to_s3($path, $self->filename);
    $self->upload_file_to_s3($thumbnail, 'thumbnail'.$self->extension);
    $self->insert;
    return $self;
}

sub fix_filename {
    my ($self, $filename) = @_;
    $filename =~ s/[^a-z0-9\_\.\-]/-/ximg;
    return $filename;
}

sub generate_thumbnail {
    my ($self, $path) = @_;
    my ($fh, $filename) = tempfile(undef, SUFFIX => $self->extension);
    my $image = Imager->new(file => $path) or ouch(500, Imager->errstr);
        $image = $image->scale(xpixels => $self->thumbnail_size) or ouch(500, $image->errstr);
        $image->write(file => $filename) or ouch(500, $image->errstr);
    return $path;
}

sub resize_image {
    my ($self, $path) = @_;
    my $image = Imager->new(file => $path) or ouch(500, Imager->errstr);
    if ($image->getwidth > $self->max_image_size) {
        $image = $image->scale(xpixels => $self->max_image_size) or ouch(500, $image->errstr);
        $image->write(file => $path) or ouch(500, $image->errstr);
    }
    return $path;
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
        );
    },
);

sub upload_file_to_s3 {
    my ($self, $path, $filename) = @_;
    my $config = Wing->config;
    my %types = (
        PNG     => "image/png",
        JPEG    => "image/jpeg",
    );
    my $type = $types{$self->file_type} || 'application/octet-stream';
    my $s3 = $self->s3;
    my $bucket = $s3->bucket($config->get('aws/'.$self->s3_bucket_name));
    my $log = Wing->log;
    $log->info('Uploading file '.$path.' to S3.');
    my $success = eval { $bucket->add_key_filename(
        $self->image_relationship_id.'/'.$self->id.'/'.$filename,
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
    $out->{image_uri} = $self->image_uri;
    $out->{thumbnail_uri} = $self->thumbnail_uri;
    if ($options{include_related_objects}) {
        $out->{metadata} = $self->metadata;
    }
    return $out;
};

1;

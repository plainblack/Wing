#!/usr/bin/env perl

BEGIN {
 die "Must set WING_HOME environment variable." unless $ENV{WING_HOME};
 die "Must set WING_APP environment variable." unless $ENV{WING_APP};
 die "Must set WING_CONFIG environment variable." unless $ENV{WING_CONFIG};
}

use lib $ENV{WING_APP}.'/lib', $ENV{WING_HOME}.'/lib';

use Wing;
use Wing::Perl;
use Template;
use Getopt::Long;
use File::Path qw(make_path);
use Ouch;

my $class_name;

GetOptions("c|class=s" => \$class_name,);

unless ($class_name) {
    say "usage: ./wing_template_class --class=NewObject";
    exit;
}

my $wing_templates = $ENV{WING_HOME}.'/var/template_class/';
my $app_templates = $ENV{WING_APP}.'/views/'.lc($class_name);

say "Creating directory $app_templates";

make_path($app_templates);
    #or die "Could not create dir $app_templates: $!\n";

my $project = Wing->config->get('app_namespace');

my $object = Wing->db->resultset($class_name)->new({});

my $t_alt = Template->new({ABSOLUTE => 1, START_TAG => quotemeta('[%['), END_TAG => quotemeta(']%]')});

eval {
    my $vars = {
        project => $project,
        class_name => $class_name,
        lower_class => lc $class_name,
        #Edit
        postable_params => $object->postable_params,
        required_params => $object->required_params,
        admin_postable_params => $object->admin_postable_params,
        #View
        public_params         => $object->public_params,
        private_params        => $object->private_params,
        admin_viewable_params => $object->admin_viewable_params,
    };
    $t_alt->process($wing_templates.'/index.tt', $vars, $app_templates.'/index.tt') || die $t_alt->error();
    $t_alt->process($wing_templates.'/view_edit.tt', $vars, $app_templates.'/view_edit.tt') || die $t_alt->error();
};

if ($@) {
    say bleep;
}
else {
    say $class_name, ' templated';
}


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
    say "usage: ./wing_add_class --class=NewObject";
    exit;
}

my $tt = Template->new({ABSOLUTE => 1});

my $project = Wing->config->get('app_namespace');

my $vars = {
    project => $project,
    class_name => $class_name,
};

eval {
  $tt->process($ENV{WING_HOME}.'/var/add_class/DB/Result.tt', $vars, $ENV{WING_APP}.'/lib/'.$project.'/DB/Result/'.$class_name.'.pm') || die $tt->error();
  $tt->process($ENV{WING_HOME}.'/var/add_class/Rest/Rest.tt', $vars, $ENV{WING_APP}.'/lib/'.$project.'/Rest/'.$class_name.'.pm') || die $tt->error();
  $tt->process($ENV{WING_HOME}.'/var/add_class/Web/Web.tt', $vars, $ENV{WING_APP}.'/lib/'.$project.'/Web/'.$class_name.'.pm') || die $tt->error();

{
    local ($^I, @ARGV) = ('', $ENV{WING_APP}.'/bin/rest.psgi');
    my $added = 0;
    while (<>) {
        next if $added;
        next unless /Wing::Rest::NotFound/;
        $added = 1;
        say "use ".$project."::Rest::".$class_name.';';
    }
    continue {
        print;
    }
}

{
    local ($^I, @ARGV) = ('', $ENV{WING_APP}.'/bin/web.psgi');
    my $added = 0;
    while (<>) {
        next if $added;
        next unless /Wing::Web::NotFound/;
        $added = 1;
        say "use ".$project."::Web::".$class_name.';';
    }
    continue {
        print;
    }
}

};

if ($@) {
    say bleep;
}
else {
    say $class_name, ' created';
}


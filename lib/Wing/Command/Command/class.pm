package Wing::Command::Command::class;

use Wing;
use Wing::Perl;
use Wing::Command -command;
use Ouch;
use File::Path qw(make_path);
use Template;

sub abstract { 'authoring tools for wing classes' }

sub usage_desc { 'Tools that auto-generate code, templates, and more for Wing classes.' }

sub description { 'Examples:
wing class --add MyClass

wing class --template MyClass

'};

sub opt_spec {
    return (
      [ 'add=s', 'generate a skeleton class' ],
      [ 'template=s', 'generate a set of skeleton templates for a class' ],
      [ 'test=s', 'generate a set of skeleton tests for a class' ],
    );
}

sub validate_args {
    my ($self, $opt, $args) = @_;
    # no args allowed but options!
    $self->usage_error("No args allowed, only options.") if @$args;
}

sub execute {
    my ($self, $opt, $args) = @_;
    if ($opt->{add}) {
        add_class($opt->{add});
    }
    elsif ($opt->{template}) {
        template_class($opt->{template});
    }
    elsif ($opt->{test}) {
        test_class($opt->{test});
    }
}

sub add_class {
    my $class_name = shift;
    my $tt = Template->new({ABSOLUTE => 1});
    
    my $project = Wing->config->get('app_namespace');
    my $project_lib = $ENV{WING_APP}.'/lib/'.$project;
    
    my $vars = {
        project => $project,
        class_name => $class_name,
    };
    
    eval {
      $tt->process($ENV{WING_HOME}.'/var/add_class/DB/Result.tt', $vars, $project_lib.'/DB/Result/'.$class_name.'.pm') || die $tt->error();
      $tt->process($ENV{WING_HOME}.'/var/add_class/Rest/Rest.tt', $vars, $project_lib.'/Rest/'.$class_name.'.pm') || die $tt->error();
      $tt->process($ENV{WING_HOME}.'/var/add_class/Web/Web.tt', $vars,   $project_lib.'/Web/'.$class_name.'.pm') || die $tt->error();
    
    {
        local ($^I, @ARGV) = ('', $project_lib.'/Rest.pm');
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
        local ($^I, @ARGV) = ('', $project_lib.'/Web.pm');
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
}

sub test_class {
    my $class_name = shift;
    my $tt = Template->new({ABSOLUTE => 1});
    
    my $project = Wing->config->get('app_namespace');
    my $project_lib = $ENV{WING_APP}.'/lib/'.$project;
    my $object = Wing->db->resultset($class_name)->new({});
    
    my $app_tests = $ENV{WING_APP}.'/t';
    say "Creating directory $app_tests";
    make_path($app_tests);

    my $vars = {
        app_namespace => $project,
        class_name => $class_name,
        lower_class => lc $class_name,
        required_params => $object->required_params,
        wing_app_path => $ENV{WING_APP},
        wing_home_path => $ENV{WING_HOME},
    };
    
    eval {
      $tt->process($ENV{WING_HOME}.'/var/test_class/Result.tt', $vars, $app_tests.'/50_result_'.$class_name.'.t') || die $tt->error();
      $tt->process($ENV{WING_HOME}.'/var/test_class/Rest.tt', $vars, $app_tests.'/70_rest_'.$class_name.'.t') || die $tt->error();
    };
    
    if ($@) {
        say bleep;
    }
    else {
        say $class_name, ' test created';
    }
}

sub template_class {
    my $class_name = shift;
    my $wing_templates = $ENV{WING_HOME}.'/var/template_class';
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
            field_options => $object->field_options,
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
        $t_alt->process($wing_templates.'/view.tt', $vars, $app_templates.'/view.tt') || die $t_alt->error();
        $t_alt->process($wing_templates.'/edit.tt', $vars, $app_templates.'/edit.tt') || die $t_alt->error();
    };
    
    if ($@) {
        say bleep;
    }
    else {
        say $class_name, ' templated';
    }
}

1;

=head1 NAME

wing class - Generate skeletons for your custom code.

=head1 SYNOPSIS

 wing class --add MyCustomClass

 wing class --template MyCustomClass
 
=head1 DESCRIPTION

This provides simple skeleton generation to eliminate blank page syndrome.

=head1 AUTHOR

Copyright 2012-2013 Plain Black Corporation.

=cut

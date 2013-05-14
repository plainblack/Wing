package Wingman::Role::Plugin;

=head1 NAME

Wingman::Role::Plugin - A required component for all Wingman plugins.

=head1 SYNOPSIS

 with 'Wingman::Role::Plugin';

=head1 DESCRIPTION

Include this in all your plugins.

=cut

use Moose::Role;

requires 'run';

=head1 INTERFACE

You must have these methods in your plugins for them to function.

=head2 run ( job, args )

This method is where you put your code. You can give it a return value if you want, but Wingman will disregard the return value.

=over

=item job

The L<Wingman::Job> object that is running this plugin. 

B<IMPORTANT:> You must do something with the job in your C<run> method. Usually what you'll want to do is call C<delete> if everything processed properly. However, in some cases you may wish to alter the flow control a little. For example, if you have a long-running process you mway wish to reset the TTR  (by C<touch()>ing it) so that Wingman doesn't kill the process mid-way through. 

=item args

A hash reference containing the arguments that the job creator passed into the job.

=back

=head1 PLUGIN DEVELOPMENT

Developing Wingman plugins is simple. You just need a package that uses the C<Wingman::Role::Plugin> role, and that has a C<run> method. See the following example.

 package MyApp::Wingman::MyCustomPlugin;

 use Wing::Perl;
 use Moose;
 with 'Wingman::Role::Plugin';

 sub run {
     Ê Êmy ($self, $job, $args_hashref) = @_;
      Ê Ê# ... your code here ...
        $job->delete;
 }

 1;

Once you've created your plugin, you need to add it to your wing config file.

 "wingman" : {
     ...,
     "plugins" : {
         "MyApp::Wingman::MyCustomPlugin" : {
             "phase" : "do_the_big_thing",
             "foo" : "bar",
         }
         ...,
     }
 }

The C<phase> is what your plugin will be known as in the system. You can also include other parameters as with the C<foo> parameter above. Other parameters will be passed to your plugin's constructor at instantiation time. This can be useful for passing in connection, encoding, path, and other properties.

Once you're set up with your new plugin, you can use it in your Wing app like this:

 Wingman->new->add_job('do_the_big_thing', \%args);

=cut

1;

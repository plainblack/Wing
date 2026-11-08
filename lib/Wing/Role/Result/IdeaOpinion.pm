package Wing::Role::Result::IdeaOpinion;

use Wing::Perl;
use Wing;
use Ouch;
use Moose::Role;

with 'Wing::Role::Result::Field';
with 'Wing::Role::Result::UserControlled';
with 'Wing::Role::Result::Parent';
with 'Wing::Role::Result::Trendy';

before wing_finalize_class => sub {
    my ($class) = @_;
    $class->wing_fields(
        idea_id         => {
            dbic        => { data_type => 'char', size => 36, is_nullable => 0 },
            edit        => 'required',
            view        => 'public',
        },
        opinion         => {
            dbic        => { data_type => 'varchar', size => 4, is_nullable => 0 },
            edit        => 'required',
            view        => 'public',
            options     => [qw(yes skip)],
            _options    => { yes => 'Yes', skip => 'Skip' },
            indexed     => 'index',
        },
    );
    my $namespace = $class;
    $namespace =~ s/^(\w+)\:.*$/$1/;
    $class->wing_parent(
        idea   => {
            view                => 'public',
            edit                => 'required',
            related_class       => $namespace.'::DB::Result::Idea',
        }
    );
};

around sqlt_deploy_hook => sub {
    my ($orig, $self, $sqlt_table) = @_;
    $sqlt_table->add_index(name => 'idx_hasvoted', fields => ['idea_id','user_id',]);
};

after insert => sub {
    my $self = shift;
    $self->log_trend('idea_voted', 1);
};

my $update_stats = sub {
    my $self = shift;
    my $idea = $self->result_source->schema->resultset('Idea')->find($self->idea_id);
    $idea->update_stats;
};

after insert => $update_stats;
after update => $update_stats;
after delete => $update_stats;


1;

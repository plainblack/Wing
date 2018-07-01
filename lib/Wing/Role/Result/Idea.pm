package Wing::Role::Result::Idea;

use Wing::Perl;
use Wing;
use Ouch;
use Moose::Role;

use POSIX qw/ceil/;
use Time::Duration;
with 'Wing::Role::Result::Field';
with 'Wing::Role::Result::Child';
with 'Wing::Role::Result::Parent';
with 'Wing::Role::Result::UserControlled';
with 'Wing::Role::Result::UriPart';
with 'Wing::Role::Result::Trendy';

no warnings 'experimental::smartmatch';

before wing_finalize_class => sub {
    my ($class) = @_;
    $class->wing_fields(
        name            => {
            dbic        => { data_type => 'varchar', size => 60, is_nullable => 0 },
            edit        => 'required',
            view        => 'public',
        },
        description     => {
            dbic        => { data_type => 'text', is_nullable => 0 },
            edit        => 'required',
            view        => 'public',
        },
        yes             => {
            dbic        => { data_type => 'bigint', is_nullable => 1, default_value => 0 },
            view        => 'public',
            indexed     => 'index',
        },
        skip            => {
            dbic        => { data_type => 'bigint', is_nullable => 1, default_value => 0 },
            view        => 'public',
            indexed     => 'index',
        },
        comment_count            => {
            dbic        => { data_type => 'int', is_nullable => 1, default_value => 0 },
            view        => 'public',
        },
        subscription_count            => {
            dbic        => { data_type => 'int', is_nullable => 1, default_value => 0 },
            view        => 'public',
        },
        locked          => {  ##AKA closed
            dbic        => { data_type => 'tinyint', is_nullable => 1, default_value => 0 },
            view        => 'public',
            edit        => 'postable',
        },
        locked_status   => {
            dbic        => { data_type => 'varchar', size => 20, is_nullable => 0, default_value => 'Unlocked', },
            view        => 'public',
            edit        => 'postable',
            options     => [qw/Infeasible Completed Merged Unlocked/],
        },
    );
    my $namespace = $class;
    $namespace =~ s/^(\w+)\:.*$/$1/;
    $class->wing_parent(
        merged_into    => {
            related_class   => $namespace.'::DB::Result::Idea',
            view            => 'public',
            edit            => 'postable',
        }
    );
    $class->wing_children(
        opinions    => {
            view            => 'public',
            related_class   => $namespace.'::DB::Result::IdeaOpinion',
            related_id      => 'idea_id',
        },
        subscriptions    => {
            view            => 'public',
            related_class   => $namespace.'::DB::Result::IdeaSubscription',
            related_id      => 'idea_id',
        },
        comments    => {
            view            => 'public',
            related_class   => $namespace.'::DB::Result::IdeaComment',
            related_id      => 'idea_id',
        }
    );
};

before delete => sub {
    my $self = shift;
    $self->opinions->delete_all;
};

after insert => sub {
    my $self = shift;
    $self->log_trend('idea_created', 1);
    $self->add_subscription($self->user_id);
};

sub view_uri {
    return join '/', '/idea', $_[0]->id, $_[0]->uri_part;
}

sub remove_subscription {
    my ($self, $user_id) = @_;
    my $subscription = $self->subscriptions->find({user_id => $user_id});
    if (defined $subscription) {
        $subscription->delete;
    }
    return $subscription;
}

sub add_subscription {
    my ($self, $user_id) = @_;
    my $subscription = $self->subscriptions->find({user_id => $user_id});
    unless (defined $subscription) {
        $subscription = $self->subscriptions->new({});
        $subscription->user_id($user_id);
        $subscription->insert;
    }
    return $subscription;
}

around describe => sub {
    my ($orig, $self, %options) = @_;
    my $out = $orig->($self, %options);
    $out->{view_uri} = $self->view_uri;
    $out->{age} = $self->age;
    if (exists $options{include} && ref $options{include} eq 'ARRAY') {
        if ('rank' ~~ $options{include} && $options{current_user}) {
            $out->{rank} = $self->rank;
        }
        if ('mysubscription' ~~ $options{include} && $options{current_user}) {
            my $subscription = $self->subscriptions->search({user_id => $options{current_user}->id},{rows => 1})->single;
            if (defined $subscription) {
                $out->{mysubscription} = $subscription->describe(include_private => 1, current_user => $options{current_user});
            }
        }
        if ('myopinion' ~~ $options{include} && $options{current_user}) {
            my $opinion = $self->opinions->search({user_id => $options{current_user}->id},{rows => 1})->single;
            if (defined $opinion) {
                $out->{myopinion} = $opinion->describe(include_private => 1, current_user => $options{current_user});
            }
        }
    }
    return $out;
};

sub age {
    my $self = shift;
    return Time::Duration::duration( $self->date_created->subtract( seconds => time() )->epoch, 1 );
}

sub rank {
    my $self = shift;
    my $rank = Wing->db->resultset('Idea')->search({
        yes => { '>' => $self->yes },
        locked => 0,
    });
    return $rank->count+1;
}

sub sorts {
    my $self = shift;
    return (
        'Score'         => {'-desc' => 'yes'},
        'Newest'        => {'-desc' => 'date_created'},
        'Last Updated'  => {'-desc' => 'date_updated'},
        'Alphabetical'  => 'name',
    );
}

sub default_sort {
    return 'Score';
}

sub search_ideas {
    my ($class, $params, $user) = @_;

    # decide sort
    my %sorts = $class->sorts;
    my $query = {};
    my $options = {
        order_by => $sorts{$params->{_sort_by}} || $sorts{$class->default_sort},
    };

    my ($keyword_clause, $filter_clause, $owner_clause, $locked_clause);
    # define query parameters
    if ($params->{'keyword'}) {
        $query->{'-or'} = [
            name        => { 'like', '%' . $params->{keyword} . '%'},
            description => { 'like', '%' . $params->{keyword} . '%'},
        ];
    }

    if ($params->{_sort_whose} eq 'Mine') {
        $query->{user_id} = $user->id;
    }

    if ($params->{_sort_status} eq 'Closed') {
        $query->{locked} = 1;
    }
    elsif ($params->{_sort_status} eq 'Infeasible') {
        $query->{locked} = 1;
        $query->{locked_status} = 'Infeasible';
    }
    elsif ($params->{_sort_status} eq 'Completed') {
        $query->{locked} = 1;
        $query->{locked_status} = 'Completed';
    }
    elsif ($params->{_sort_status} eq 'Merged') {
        $query->{locked} = 1;
        $query->{locked_status} = 'Merged';
    }
    elsif ($params->{_sort_status} eq 'Open') {
        $query->{locked} = 0;
    }
    ##Implicit case for All, which is don't care about locked and locked_status

    # return resultset
    my $ideas = Wing->db->resultset('Idea')->search($query, $options);
    return $ideas;
}

sub update_stats {
    my $self = shift;
    my $opinions = $self->opinions;
    $self->yes($opinions->search({opinion=>'yes'})->count);
    $self->skip($opinions->search({opinion=>'skip'})->count);
    $self->update;
}

sub merge {

    my $self = shift;
    my $old_idea = shift;    # merge this idea into us

    my $sth = Wing->db->storage->dbh->prepare(qq{
        select
            opinion1.user_id as user_id,
            opinion1.id as old_opinion_id,
            opinion1.opinion as old_opinion,
            opinion2.id as new_opinion_id,
            opinion2.opinion as new_opinion
        from ideaopinions opinion1
        join ideas idea1 on opinion1.idea_id = idea1.id and idea1.id = ?
        join ideas idea2 on idea2.id = ?
        left join ideaopinions opinion2 on opinion1.user_id = opinion2.user_id and opinion2.idea_id = idea2.id
    });

    $sth->execute(
        $old_idea->id,
        $self->id,
    );

    # based on the decision table in https://github.com/plainblack/MobRater/issues/11

    while( my $row = $sth->fetchrow_hashref ) {
        if( defined $row->{old_opinion} and ! defined $row->{new_opinion} ) {
            # move over the old opinion to the new idea
            Wing->db->resultset('IdeaOpinion')->search({ id => $row->{old_opinion_id} })->update({ idea_id => $self->id, });
            # warn "scenario 6";
        } elsif( $row->{old_opinion} ne $row->{new_opinion} ) {
            Wing->db->resultset('IdeaOpinion')->search({ id => $row->{new_opinion_id} })->delete_all;   # the old one will be deleted too
            # warn "scenario 1 or 2";
        } elsif( $row->{old_opinion} eq $row->{new_opinion} ) {
            # warn "scenario 3 or 4";
        }

    }

    $self->update_stats;
    $old_idea->locked(1);
    $old_idea->locked_status('Merged');
    $old_idea->merged_into($self);
    $old_idea->opinions->delete;
    $old_idea->update_stats;  ##also calls update

    $old_idea->notify_subscribers('Idea merged into: '.$self->name);

    my $old_subs = $old_idea->subscriptions;
    while (my $old_sub = $old_subs->next) {
        $self->add_subscription($old_sub->user_id);
    }

    return $self;
}

sub lock {
    my ($self, $message) = @_;
    $self->locked(1);
    $self->locked_status($message);
    $self->update;
    $self->notify_subscribers('Idea Closed: '.$message);
}

sub unlock {
    my ($self) = @_;
    $self->locked(0);
    $self->locked_status('Unlocked');
    $self->merged_into(undef);
    $self->update;
    $self->notify_subscribers('Idea Reopened');
}

sub notify_subscribers {
    my ($self, $message, $user_id) = @_;
    my $subscriptions = $self->subscriptions;
    while (my $subscription = $subscriptions->next) {
        $subscription->notify($message, $user_id);
    }
}

sub recalc_comment_count {
    my ($self) = @_;
    $self->comment_count($self->comments->count);
    $self->update;
}

sub recalc_subscription_count {
    my ($self) = @_;
    $self->subscription_count($self->subscriptions->count);
    $self->update;
}

1;

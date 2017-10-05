use lib '/data/Wing/author.t/lib','/data/Wing/lib';
use Test::More;
use Wing::Perl;
use Wing;

my $users = Wing->db->resultset('User');
my $owner = $users->new({
    username    => 'guard',
    real_name   => 'Byron T. Hadley',
    email       => 'guard@shawshank.jail',
    admin       => 0,
    use_as_display_name => 'real_name', 
});
$owner->insert;    
isa_ok($owner, 'TestWing::DB::Result::User');
my $user = $users->new({
    username    => 'andy',
    real_name   => 'Andy Dufresne',
    email       => 'andy@shawshank.jail',
    admin       => 0,
    use_as_display_name => 'real_name', 
});
$user->insert;    
isa_ok($user, 'TestWing::DB::Result::User');
my $admin = $users->new({
    username    => 'warden',
    real_name   => 'Samuel Norton',
    email       => 'warden@shawshank.jail',
    admin       => 1,
    use_as_display_name => 'real_name', 
});
$admin->insert;    
isa_ok($admin, 'TestWing::DB::Result::User');

my $secret = 'ledger in safe';
my $name = 'Shawshank Prison';
my $company = Wing->db->resultset('Company')->new({
    name            => $name,
    private_info    => $secret,
});
$company->insert;
isa_ok($company, 'TestWing::DB::Result::Company');

is($company->name, $name, 'name is what we expect');
is($company->private_info, $secret, 'secret is what we expect');

eval { 
    $company->verify_posted_params({
        name            => 'Home',
        private_info    => 'Nothing',
    }, $user);
};

is($company->name, $name, 'name is still what we expect');
is($company->private_info, $secret, 'secret is still what we expect');

eval { 
    $company->verify_posted_params({
        name            => 'Hustle',
        private_info    => 'my retirement fund',
    }, $admin);
};

is($company->name, 'Hustle', 'name has been changed');
is($company->private_info, 'my retirement fund', 'secret is has been changed');

$company->is_owner(1);
eval { 
    $company->verify_posted_params({
        name            => 'Work',
        private_info    => 'paycheck',
    }, $owner);
};

is($company->name, 'Work', 'name has been changed again');
is($company->private_info, 'my retirement fund', 'secret is has NOT been changed');
$company->privilege_switch(1);

eval { 
    $company->verify_posted_params({
        name            => 'Work Again',
        private_info    => 'paycheck',
    }, $owner);
};

is($company->name, 'Work Again', 'name has been changed again');
is($company->private_info, 'paycheck', 'secret is has NOT been changed');

$company->is_owner(0);
eval { 
    $company->verify_posted_params({
        private_info    => 'Rita Hayworth',
    }, $user);
};

is($company->name, 'Work Again', 'name has been NOT been changed again');
is($company->private_info, 'Rita Hayworth', 'secret is has also been changed');



done_testing;

END {
    $user->delete;
    $admin->delete;
    $company->delete;
    $owner->delete;
}

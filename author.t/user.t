use lib '/data/Wing/author.t/lib','/data/Wing/lib';
use Test::More;
use Wing::Perl;
use Wing;
use Encode;
use Crypt::Eksblowfish::Bcrypt;

my $password = 'testme';

my $md5_password = 'YjGKyi7y6AmhNiNxWoqv9A';

my $bcrypt_password = '.pMtfs4tOD3AcJ44EixNAPJxHCP/E3a';
my $bcrypt_salt = 'FS863GXed3YMX6e3';

my $user = Wing->db->resultset('User')->new({});
isa_ok $user, 'TestWing::DB::Result::User';
$user->username('_bubba_');
$user->encrypt_and_set_password($password);
$user->insert;

my $key = Wing->db->resultset('APIKey')->new({user_id => $user->id, name => 'Key for User', })->insert;
my $perm = Wing->db->resultset('APIKeyPermission')->new({user_id => $user->id, api_key_id => $key->id, permission => 'view_my_account', })->insert;

ok $user->is_password_valid($password), 'can create and test a password';

$user->password($md5_password);
$user->password_type('md5');
$user->update;

ok $user->is_password_valid($password), 'can upgrade an md5 password';
is $user->password_type, 'bcrypt', 'password type is changed';

$user->password($bcrypt_password);
$user->password_salt($bcrypt_salt);
$user->password_type('bcrypt');
$user->update;

ok $user->is_password_valid($password), 'known working bcrypt password';

my $user_api_keys = Wing->db->resultset('APIKey')->search({user_id => $user->id, });
my $user_api_perms = Wing->db->resultset('APIKey')->search({user_id => $user->id, });
is $user_api_keys->count, 1, 'User has 1 API key';
is $user_api_perms->count, 1, 'User has 1 API key permission';

my $json = $user->user_to_json;
is $json->{username}, $user->username, 'user_to_json includes the columns';
ok !ref $json->{date_created}, 'user_to_json formats dates as MySQL strings';
my $copy = ref($user)->user_from_json(Wing->db, $json);
is $copy->id, $user->id, 'user_from_json rebuilds the user';
ok $copy->in_storage, 'user_from_json marks the user as stored';

$user->delete;
is $user_api_keys->count, 0, 'API Key cleaned up for user';
is $user_api_perms->count, 0, 'API Key permission cleaned up for user';

done_testing;

END {
    use TestHelper;
    TestHelper::cleanup;
}

package Wing::Rest::APIKey;

use Wing::Perl;
use Dancer;
use Wing::Rest;

generate_options('APIKey');
generate_read('APIKey');
generate_update('APIKey', permissions => ['edit_my_account']);
generate_delete('APIKey', permissions => ['edit_my_account']);
generate_create('APIKey', permissions => ['edit_my_account']);

1;

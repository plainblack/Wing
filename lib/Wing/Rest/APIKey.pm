package Wing::Rest::APIKey;

use Wing::Perl;
use Dancer;
use Wing::Rest;

generate_crud('APIKey', permissions => ['edit_my_account']);

1;

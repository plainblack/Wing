package Wing::Rest::IdeaSubscription;

use Wing::Perl;
use Wing;
use Dancer;
use Ouch;
use Wing::Rest;

generate_crud('IdeaSubscription');
generate_all_relationships('IdeaSubscription');

1;

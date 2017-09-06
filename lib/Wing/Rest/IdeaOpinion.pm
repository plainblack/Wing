package Wing::Rest::IdeaOpinion;

use Wing::Perl;
use Dancer;
use Wing::Rest;
use Wing::Dancer;

generate_crud('Opinion');
generate_all_relationships('IdeaOpinion');

1;

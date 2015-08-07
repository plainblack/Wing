package [% project %]::Web;

use Dancer;
# your modules here
use Wing::Template; ## Should be the LAST hook added for processing templates.
use Wing::Web::Account;
use Wing::Web::Admin::User;
use Wing::Web::Admin::Wingman;
use Wing::Web::Admin::Trends;
use Wing::Web::NotFound;

1;

This is the code you'd need to create an ideas system like the one you see here: https://component.studio/ideas

You'll need to copy the files into place and modify as needed as there is no installer. 

Also, add this to your lib/MyApp/Rest.pm file:

use Wing::Rest::Idea;
use Wing::Rest::IdeaOpinion;
use Wing::Rest::IdeaSubscription;
use Wing::Rest::IdeaComment;

And this to your lib/MyApp/Web.pm file:

use Wing::Web::Ideas;


#!/data/apps/bin/perl -pi

# migrate models and autosaves
if (/^\s*<(select)/i) {
    my ($formname) = m/ng-model="\w+.properties.(\w+)"/;
    s/autosave=.(\w+)./\@change="$1\.save('$formname')"/;
    s/\sng-model=/ v-model=/;
}
if (/^\s*<(input|textarea)/i) {
    s/\sautosave=/ v-autosave=/;
    s/\sng-model=/ v-model=/;
}

# migrate responsive images
s/img-responsive/img-fluid/;

# migrate columns
s/col-xs-/col-/;

# migrate floats
s/pull-right/float-right/;

# migrate buttons
s/\sng-click=/ \@click=/;

# migrate loops
s/\sng-repeat=/ v-for=/;

# migrate conditions
s/\sng-if=/ v-if=/;
s/\sng-show=/ v-show=/;
s/\sng-hide="/ v-show="!/;
s/\sng-hide='/ v-show='!/;

# migrate wing-select
if (/^\s*<(wing-select)/i) {
    s/\sobject=/ :object=/;
}

# migrate help-block
s/help-block/form-text text-muted/g;
s/<(div|p|span) class="form-text text-muted">(.*?)<\/(div|p|span)>/<small class="form-text text-muted">$2<\/small>/i;
#s/<small class="form-text text-muted">(.*?)<\/small>/<b-form-text>$1<\/b-form-text>/i;

# migrate default buttons to secondary buttons
s/btn-default/btn-secondary/g;

# remove fieldsets
s/<fieldset>//g;
s/<\/fieldset>//g;
s/<legend>(.*?)<\/legend>/<h2>$1<\/h2>/g;

# remove horizontal forms
if (/^\s*<(form)/) {
    s/\sclass="form-horizontal"//;
}
if (/^\s*<(label)/) {
    s/\sclass="col-sm-4 control-label"//;
}

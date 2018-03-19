#!/data/apps/bin/perl -pi

# migrate models and autosaves
if (/^\s*<(input|textarea|select)/) {
    my ($formname) = m/ng-model="\w+.properties.(\w+)"/;
    s/autosave=.(\w+)./\@blur="$1\.save('$formname')"/;
    s/ng-model/v-model/;
}

# migrate wing-select
if (/^\s*<(wing-select)/) {
    s/\sobject=/ :object=/;
}

# migrate help-block
s/help-block/form-text text-muted/g;

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

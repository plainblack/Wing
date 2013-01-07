jQuery.ajaxSettings.traditional = true;
var wing = new Object();

wing.info = function(message) {
    $.pnotify({
        type: 'info',
        title: 'Info',
        text: message,
        icon: 'picon icon16 brocco-icon-info white',
        opacity: 0.95,
        hide: false,
        history: false,
        sticker: false
    });
};

wing.warn = function(message) {
    $.pnotify({
        title: 'Warning',
        text: message,
        icon: 'picon icon16 entypo-icon-warning white',
        opacity: 0.95,
        hide: false,
        history: false,
        sticker: false
    });
};

wing.error = function(message) {
    $.pnotify({
        type: 'error',
        title: 'Error',
        text: message,
        icon: 'picon icon24 typ-icon-cancel white',
        opacity: 0.95,
        hide:false,
        history: false,
        sticker: false
    });
};

wing.success = function(message) {
    $.pnotify({
        type: 'success',
        title: 'Success',
        text: message,
        icon: 'picon icon16 iconic-icon-check-alt white',
        opacity: 0.95,
        history: false,
        sticker: false
    });
};

wing.ajax = function(method, uri, params, success) {
    jQuery.ajax('/api/'+uri, {
        type : method,
        data : params,
        dataType : "json",
        success : function(data, text_status, jqxhr) {
            if (data.result._warnings) {
                for (var warning in data.result._warnings) {
                    wing.warn(data.result._warnings[warning].message);
                }
            }
            success(data, text_status, jqxhr);
        },
        error : function(jqxhr, text_status, error_thrown) {
            var result = jQuery.parseJSON(jqxhr.responseText);
            if (result.error) {
                var message = result.error.message;
                var matches = message.split(/ /);
                var field = matches[0].toLowerCase();
                var label = $('label[for="'+field+'"]').text();
                if (label) {
                    message = message.replace(field,label);
                }
                wing.error(message);
            }
            else {
                wing.error('Error communicating with server.');
            }
        }
    });
};

wing.update_field = function(uri, id, callback) {
    var field = $('#'+id);
    var params = {};
    var field_name = field.attr('name');
    if (typeof field_name == 'undefined') {
        wing.error('Field id "'+id+'" does not have a field name associated with it.');
    }
    params[field_name] = field.val();
    wing.ajax('PUT', uri, params, function(){
        callback();
        wing.success('Saved '+ $('label[for="'+id+'"]').text()+'.');
    });
};

wing.delete_object = function(wing_object_type, id) {
    if (confirm('Are you sure you want to delete it?')) {
        wing.ajax('DELETE', wing_object_type + '/' + id, {}, function(){
            wing.success('Deleted!');
            $('#'+id).remove();
        });
    }
};

wing.attach_autosave = function(uri, save_class) {
    $(save_class).each(function(index, tag) {
        var id = $(tag).attr('id');
        $('#'+id).change(function(){
            wing.update_field(uri, id, function() {});
        });
    });
};

// Consume Javascript Alerts
window.alert = function(message) {
    $.pnotify({
        title: 'Alert',
        hide: false,
        text: message
    });
};

wing.enable_blink = function() {
        window.blinker = setInterval(function(){
        if(window.blink){
           $('.blink').delay(500).animate({color:'#000'},500);
           window.blink=false;
         }
        else{
                $('.blink').animate({color:'#f00'},500);
                window.blink = true;
        }
    },500);
};

wing.pager = function(selector, callback, data) {
    $(selector).pagination(data.result.paging.total_items, {
          items_per_page : data.result.paging.items_per_page,
          callback: callback,
          num_edge_entries : 1,
          num_display_entries : 4,
          prev_text : "|&#9664;",
          next_text : "&#9654;|",
          current_page : (data.result.paging.page_number - 1),
          load_first_page : false,
          link_to : 'javascript:void(0)'
      });  
};

wing.populate = function(uri, params, ids, extra) {
    wing.ajax('GET', uri, params, function(data, text_status, jqxhr) {
        var object = data.result;
        for (var i in ids) {
            var field_id = ids[i];
            var field = $('#'+ids[i]);
            var field_name = field.attr('name');
            if (typeof field_name == 'undefined') {
                field_name = field_id;
            }
            if (field.is('input') || field.is('textarea')) { // populate form elements
                field.val(object[field_name]);
                if ('_options' in object && field_name in object._options) {
                    var options = object._options[field_name];
                    var labels = object._options['_'+field_name];
                    var field_options = [];
                    for (var j in options) {
                        field_options.push({
                            id :    options[j],
                            text:   labels[options[j]]
                        });
                    }
                    $('#'+field_id).select2({
                        data:   field_options,
                        initSelection : function(element, callback) {
                            callback({
                                id: field.val(),
                                text: labels[field.val()]
                            });
                        }
                    });
                } 
            }
            else { // populate divs and whatnot
                field.html(object[field_name]);
            }
        }
        if (typeof extra != 'undefined') {
            extra(object);
        }
    });    
};


wing.show_window = function(uri) {
    if (!uri) {
        uri = '/filesystem';
    }
    $('#fs_modal_iframe').prop('src', uri);
    $('#fs_modal').modal({show: true });
};

wing.hide_window = function() {
    $('#fs_modal').modal('hide');
};

wing.current_callback = function() {
    wing.error('No callback specified');
};

wing.choose_file = function(file, expected_type, postback_uri, open_uri) {
    wing.current_callback = function(id, preview_uri, type) {
        var error_message = '';
        if (expected_type == 'image') {
            if (type != 'JPEG' && type != 'PNG') {
                error_message = 'Expected you to choose an image, but you chose a PDF.';
            }
        }
        else if (expected_type != type) {
            error_message = 'Expected you to choose a PDF, but you chose an image.';
        }
        if (error_message != '') {
            wing.error(error_message);
        }
        else {
            document.getElementById(file + '_id').value = id;
            var file_field = $('#'+file + '_id');
            var proofed_field = $('#has_proofed_'+file);
            var params = {};
            params[file_field.attr('name')] = file_field.val();
            params[proofed_field.attr('name')] = 0;
            wing.ajax('PUT', postback_uri, params, function(){
                wing.hide_window();
                document.getElementById(file).src = preview_uri;
                $('#has_proofed_' + file).val(0);
                $('#has_proofed_' + file + '_button').addClass('red');
                wing.success('Saved '+ $('label[for="'+file + '_id'+'"]').text()+'.');
            });
        }
    };
    wing.show_window(open_uri);
};


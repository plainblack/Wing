jQuery.ajaxSettings.traditional = true;
jQuery.ajaxSettings.cache = false;

var wing = new Object();

wing.info = function(message) {
    $.pnotify({
        type: 'info',
        title: 'Info',
        text: message,
        icon: 'picon icon16 brocco-icon-info white',
        opacity: 0.95,
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
    if (!uri.match(/\/api/)) {
        uri = '/api/' + uri;
    }
    wing.display_throbber();
    jQuery.ajax(uri, {
        type : method,
        data : params,
        dataType : "json",
        success : function(data, text_status, jqxhr) {
    	    wing.hide_throbber();
            if (data.result._warnings) {
                for (var warning in data.result._warnings) {
                    wing.warn(data.result._warnings[warning].message);
                }
            }
            success(data, text_status, jqxhr);
        },
        error : function(jqxhr, text_status, error_thrown) {
    	    wing.hide_throbber();
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
    return false;
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

// auto-populate a page with data from an ajax call
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


jQuery.fn.pagination = function(maxentries, opts){
    opts = jQuery.extend({
        items_per_page:10,
        num_display_entries:10,
        current_page:0,
        num_edge_entries:0,
        link_to:"javascript:void(0)",
        prev_text:"Prev",
        next_text:"Next",
        ellipse_text:"...",
        prev_show_always:true,
        next_show_always:true,
        callback:function(){return false;}
    },opts||{});

    return this.each(function() {
        /**
         * Calculate the maximum number of pages
         */
        function numPages() {
            return Math.ceil(maxentries/opts.items_per_page);
        }

        /**
         * Calculate start and end point of pagination links depending on 
         * current_page and num_display_entries.
         * @return {Array}
         */
        function getInterval()  {
            var ne_half = Math.ceil(opts.num_display_entries/2);
            var np = numPages();
            var upper_limit = np-opts.num_display_entries;
            var start = current_page>ne_half?Math.max(Math.min(current_page-ne_half, upper_limit), 0):0;
            var end = current_page>ne_half?Math.min(current_page+ne_half, np):Math.min(opts.num_display_entries, np);
            return [start,end];
        }

        /**
         * This is the event handling function for the pagination links. 
         * @param {int} page_id The new page number
         */
        function pageSelected(page_id, evt){
            current_page = page_id;
            drawLinks();
            var continuePropagation = opts.callback(page_id, panel);
            if (!continuePropagation) {
                if (evt.stopPropagation) {
                    evt.stopPropagation();
                }
                else {
                    evt.cancelBubble = true;
                }
            }
            return continuePropagation;
        }

        /**
         * This function inserts the pagination links into the container element
         */
        function drawLinks() {
            panel.empty();
            var list = jQuery("<ul></ul>");
            panel.append(list);

            var interval = getInterval();
            var np = numPages();
            // This helper function returns a handler function that calls pageSelected with the right page_id
            var getClickHandler = function(page_id) {
                return function(evt){ return pageSelected(page_id,evt); }
            }
            // Helper function for generating a single link (or a span tag if it's the current page)
            var appendItem = function(page_id, appendopts){
                page_id = page_id<0?0:(page_id<np?page_id:np-1); // Normalize page id to sane value
                appendopts = jQuery.extend({text:page_id+1, classes:""}, appendopts||{});
                if(page_id == current_page){
                    var clazz = appendopts.side ? 'disabled' : 'active';
                    var lstItem = jQuery("<li class='"+clazz+"'><a>"+(appendopts.text)+"</a></li>")
                }
                else
                {
                    var a = jQuery("<a>"+(appendopts.text)+"</a>")
                        .attr('href', opts.link_to.replace(/__id__/,page_id));;
                    var lstItem = jQuery("<li></li>")
                        .bind("click", getClickHandler(page_id));
                    lstItem.append(a);
                }
                if(appendopts.classes){lstItem.addClass(appendopts.classes);}
                list.append(lstItem);
            }
            // Generate "Previous"-Link
            if(opts.prev_text && (current_page > 0 || opts.prev_show_always)){
                appendItem(current_page-1,{text:opts.prev_text, side:true});
            }
            // Generate starting points
            if (interval[0] > 0 && opts.num_edge_entries > 0)
            {
                var end = Math.min(opts.num_edge_entries, interval[0]);
                for(var i=0; i<end; i++) {
                    appendItem(i);
                }
                if(opts.num_edge_entries < interval[0] && opts.ellipse_text)
                {
                    jQuery("<li class='disabled'>"+opts.ellipse_text+"</li>").appendTo(list);
                }
            }
            // Generate interval links
            for(var i=interval[0]; i<interval[1]; i++) {
                appendItem(i);
            }
            // Generate ending points
            if (interval[1] < np && opts.num_edge_entries > 0)
            {
                if(np-opts.num_edge_entries > interval[1]&& opts.ellipse_text)
                {
                    jQuery("<li class='disabled'>"+opts.ellipse_text+"</li>").appendTo(list);
                }
                var begin = Math.max(np-opts.num_edge_entries, interval[1]);
                for(var i=begin; i<np; i++) {
                    appendItem(i);
                }

            }
            // Generate "Next"-Link
            if(opts.next_text && (current_page < np-1 || opts.next_show_always)){
                appendItem(current_page+1,{text:opts.next_text, side:true});
            }
        }

        // Extract current_page from options
        var current_page = opts.current_page;
        // Create a sane value for maxentries and items_per_page
        maxentries = (!maxentries || maxentries < 0)?1:maxentries;
        opts.items_per_page = (!opts.items_per_page || opts.items_per_page < 0)?1:opts.items_per_page;
        // Store DOM element for easy access from all inner functions
        var panel = jQuery(this);
        // Attach control functions to the DOM element 
        this.selectPage = function(page_id){ pageSelected(page_id);}
        this.prevPage = function(){ 
            if (current_page > 0) {
                pageSelected(current_page - 1);
                return true;
            }
            else {
                return false;
            }
        }
        this.nextPage = function(){ 
            if(current_page < numPages()-1) {
                pageSelected(current_page+1);
                return true;
            }
            else {
                return false;
            }
        }
        // When all initialisation is done, draw the links
        drawLinks();
        // call callback function
        //opts.callback(current_page, this);
    });
}

// http://fgnass.github.com/spin.js/
!function(t,e,i){var o=["webkit","Moz","ms","O"],r={},n;function a(t,i){var o=e.createElement(t||"div"),r;for(r in i)o[r]=i[r];return o}function s(t){for(var e=1,i=arguments.length;e<i;e++)t.appendChild(arguments[e]);return t}var f=function(){var t=a("style",{type:"text/css"});s(e.getElementsByTagName("head")[0],t);return t.sheet||t.styleSheet}();function l(t,e,i,o){var a=["opacity",e,~~(t*100),i,o].join("-"),s=.01+i/o*100,l=Math.max(1-(1-t)/e*(100-s),t),p=n.substring(0,n.indexOf("Animation")).toLowerCase(),u=p&&"-"+p+"-"||"";if(!r[a]){f.insertRule("@"+u+"keyframes "+a+"{"+"0%{opacity:"+l+"}"+s+"%{opacity:"+t+"}"+(s+.01)+"%{opacity:1}"+(s+e)%100+"%{opacity:"+t+"}"+"100%{opacity:"+l+"}"+"}",f.cssRules.length);r[a]=1}return a}function p(t,e){var r=t.style,n,a;if(r[e]!==i)return e;e=e.charAt(0).toUpperCase()+e.slice(1);for(a=0;a<o.length;a++){n=o[a]+e;if(r[n]!==i)return n}}function u(t,e){for(var i in e)t.style[p(t,i)||i]=e[i];return t}function c(t){for(var e=1;e<arguments.length;e++){var o=arguments[e];for(var r in o)if(t[r]===i)t[r]=o[r]}return t}function d(t){var e={x:t.offsetLeft,y:t.offsetTop};while(t=t.offsetParent)e.x+=t.offsetLeft,e.y+=t.offsetTop;return e}var h={lines:12,length:7,width:5,radius:10,rotate:0,corners:1,color:"#000",speed:1,trail:100,opacity:1/4,fps:20,zIndex:2e9,className:"spinner",top:"auto",left:"auto",position:"relative"};function m(t){if(!this.spin)return new m(t);this.opts=c(t||{},m.defaults,h)}m.defaults={};c(m.prototype,{spin:function(t){this.stop();var e=this,i=e.opts,o=e.el=u(a(0,{className:i.className}),{position:i.position,width:0,zIndex:i.zIndex}),r=i.radius+i.length+i.width,s,f;if(t){t.insertBefore(o,t.firstChild||null);f=d(t);s=d(o);u(o,{left:(i.left=="auto"?f.x-s.x+(t.offsetWidth>>1):parseInt(i.left,10)+r)+"px",top:(i.top=="auto"?f.y-s.y+(t.offsetHeight>>1):parseInt(i.top,10)+r)+"px"})}o.setAttribute("aria-role","progressbar");e.lines(o,e.opts);if(!n){var l=0,p=i.fps,c=p/i.speed,h=(1-i.opacity)/(c*i.trail/100),m=c/i.lines;(function y(){l++;for(var t=i.lines;t;t--){var r=Math.max(1-(l+t*m)%c*h,i.opacity);e.opacity(o,i.lines-t,r,i)}e.timeout=e.el&&setTimeout(y,~~(1e3/p))})()}return e},stop:function(){var t=this.el;if(t){clearTimeout(this.timeout);if(t.parentNode)t.parentNode.removeChild(t);this.el=i}return this},lines:function(t,e){var i=0,o;function r(t,o){return u(a(),{position:"absolute",width:e.length+e.width+"px",height:e.width+"px",background:t,boxShadow:o,transformOrigin:"left",transform:"rotate("+~~(360/e.lines*i+e.rotate)+"deg) translate("+e.radius+"px"+",0)",borderRadius:(e.corners*e.width>>1)+"px"})}for(;i<e.lines;i++){o=u(a(),{position:"absolute",top:1+~(e.width/2)+"px",transform:e.hwaccel?"translate3d(0,0,0)":"",opacity:e.opacity,animation:n&&l(e.opacity,e.trail,i,e.lines)+" "+1/e.speed+"s linear infinite"});if(e.shadow)s(o,u(r("#000","0 0 4px "+"#000"),{top:2+"px"}));s(t,s(o,r(e.color,"0 0 1px rgba(0,0,0,.1)")))}return t},opacity:function(t,e,i){if(e<t.childNodes.length)t.childNodes[e].style.opacity=i}});(function(){function t(t,e){return a("<"+t+' xmlns="urn:schemas-microsoft.com:vml" class="spin-vml">',e)}var e=u(a("group"),{behavior:"url(#default#VML)"});if(!p(e,"transform")&&e.adj){f.addRule(".spin-vml","behavior:url(#default#VML)");m.prototype.lines=function(e,i){var o=i.length+i.width,r=2*o;function n(){return u(t("group",{coordsize:r+" "+r,coordorigin:-o+" "+-o}),{width:r,height:r})}var a=-(i.width+i.length)*2+"px",f=u(n(),{position:"absolute",top:a,left:a}),l;function p(e,r,a){s(f,s(u(n(),{rotation:360/i.lines*e+"deg",left:~~r}),s(u(t("roundrect",{arcsize:i.corners}),{width:o,height:i.width,left:i.radius,top:-i.width>>1,filter:a}),t("fill",{color:i.color,opacity:i.opacity}),t("stroke",{opacity:0}))))}if(i.shadow)for(l=1;l<=i.lines;l++)p(l,-2,"progid:DXImageTransform.Microsoft.Blur(pixelradius=2,makeshadow=1,shadowopacity=.3)");for(l=1;l<=i.lines;l++)p(l);return s(e,f)};m.prototype.opacity=function(t,e,i,o){var r=t.firstChild;o=o.shadow&&o.lines||0;if(r&&e+o<r.childNodes.length){r=r.childNodes[e+o];r=r&&r.firstChild;r=r&&r.firstChild;if(r)r.opacity=i}}}else n=p(e,"animation")})();if(typeof define=="function"&&define.amd)define(function(){return m});else t.Spinner=m}(window,document);

wing.display_throbber = function() {
    $('body').append('<div id="wingajaxactivity" style="position: fixed; top: 45%; left: 47%;"></div>');
    var opts = {
      lines: 11, // The number of lines to draw
      length: 0, // The length of each line
      width: 17, // The line thickness
      radius: 40, // The radius of the inner circle
      corners: 1, // Corner roundness (0..1)
      rotate: 54, // The rotation offset
      color: '#999', // #rgb or #rrggbb
      speed: 1.6, // Rounds per second
      trail: 41, // Afterglow percentage
      shadow: true, // Whether to render a shadow
      hwaccel: true, // Whether to use hardware acceleration
      className: 'wingthrobber', // The CSS class to assign to the spinner
      zIndex: 2e9, // The z-index (defaults to 2000000000)
      top: 'auto', // Top position relative to parent in px
      left: 'auto' // Left position relative to parent in px
    };
   var target = document.getElementById('wingajaxactivity');
   var spinner = new Spinner(opts).spin(target);
}
wing.hide_throbber = function() {
 $('#wingajaxactivity').remove();
}

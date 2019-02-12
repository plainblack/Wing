
/*
 * Axios global settings
 */

// send session cookie
axios.defaults.withCredentials = true;
//disable IE ajax request caching
axios.defaults.headers.get['If-Modified-Since'] = 'Mon, 26 Jul 1997 05:00:00 GMT';
//more cache control
axios.defaults.headers.get['Cache-Control'] = 'no-cache';
axios.defaults.headers.get['Pragma'] = 'no-cache';
axios.defaults.paramsSerializer = function(params) {
    return Qs.stringify(params, {arrayFormat: 'repeat'});
};
axios.interceptors.request.use(function (config) {
    wing.throbber.working();
    return config;
}, function (error) {
    wing.throbber.done();
    return Promise.reject(error);
});
axios.interceptors.response.use(function (response) {
    wing.throbber.done();
    if (response.headers['content-type'] === "application/json; charset=utf-8" && "_warnings" in response.data.result) {
        for (var warning in response.data.result._warnings) {
            document.dispatchEvent(new CustomEvent('wing_warn', { message : response.data.result._warnings[warning].message }));
            wing.warn(response.data.result._warnings[warning].message);
        }
    }
    return response;
}, function (error) {
    wing.throbber.done();
    var message = 'Error communicating with server.';
    if (_.isObject(error.response) && _.isObject(error.response.headers) && error.response.headers['content-type'] === "application/json; charset=utf-8" && "error" in error.response.data) {
        if (error.response.data.error.code == 401) {
            message = 'You must <a href="/account" class="btn btn-primary btn-sm">log in</a> to do that.';
        }
        else {
            message = error.response.data.error.message;
            var matches = message.split(/ /);
            var field = matches[0].toLowerCase();
            var label = document.querySelectorAll('label[for="'+field+'"]').innerHtml;
            if (label) {
                message = message.replace(field,label);
            }
        }
    }
    document.dispatchEvent(new CustomEvent('wing_error', { message : message }));
    wing.error(message);
    return Promise.reject(error);
});

/*
 * Throbber progress bar element
 */

var throbber = document.createElement('div');
throbber.innerHTML = `<div id="wingajaxprogress" style="z-index: 10000; position: fixed; top: 0px; width: 100%;">
    <template v-if="counter > 0"><b-progress :value="counter" :max="max" height="10px" animated></b-progress></template>
</div>`;
document.body.appendChild(throbber);



/*
 * Format a date
 */

Vue.filter('moment', function(input, format, timezone){
    if (typeof moment !== 'undefined') {
        if (!_.isString(format)) {
            format = 'MMMM D, YYYY';
        }
        return wing.parse_date(input, timezone).format(format);
    }
    return input;
});

/*
 * Format a date into a relative time
 */

Vue.filter('timeago', function(input){
    if (typeof moment !== 'undefined') {
        return wing.parse_date(input).fromNow();
    }
    return input;
});


/*
 * Round a decimal to some level of precision
 */

Vue.filter('round', function(number, precision){
    number = parseFloat(number);
    precision |= 0;
    var shift = function (number, precision, reverseShift) {
        if (reverseShift) {
          precision = -precision;
        }
        numArray = ("" + number).split("e");
        return +(numArray[0] + "e" + (numArray[1] ? (+numArray[1] + precision) : precision));
    };
    return shift(Math.round(shift(number, precision, false)), precision, true);
});


/*
 * format a file size using common bytes multiples
 */

Vue.filter('bytes', function(bytes){
    if (isNaN(parseFloat(bytes)) || !isFinite(bytes)) return '-';
    if (typeof precision === 'undefined') precision = 1;
    var units = ['bytes', 'kB', 'MB', 'GB', 'TB', 'PB'],
        number = Math.floor(Math.log(bytes) / Math.log(1024));
    return (bytes / Math.pow(1024, Math.floor(number))).toFixed(precision) +  ' ' + units[number];
});

/*
 * Automatically save an input field.
 */

Vue.directive('autosave', {
    inserted: function (el, binding, vnode) {
        const index = _.findIndex(vnode.data.directives, {rawName : 'v-model'});
        if (index == -1) {
            console.log('Cannot use v-autosave unless on an element with a v-model.');
        }
        else {
            const field = vnode.data.directives[index].expression.split(/\./)[2];
            var timer;
            var original_value = binding.value.properties[field];
            const debounce = function(e) {
                if (timer) {
                    clearTimeout(timer);
                }
                if (e.keyCode == 13 && el.tagName != 'TEXTAREA') {
                    binding.value.save(field);
                }
                else {
                    timer = setTimeout(function() {
                        if (original_value != binding.value.properties[field]) {
                            original_value = binding.value.properties[field];
                            binding.value.save(field);
                        }
                    }, 2000);
                }
            }
            el.addEventListener('keyup', debounce, false);
            el.addEventListener('change', debounce, false);
            el.addEventListener('focus', debounce, false);
            el.addEventListener('blur', function(){
                if (original_value != binding.value.properties[field]) {
                    clearTimeout(timer);
                    original_value = binding.value.properties[field];
                    binding.value.save(field);
                }
            }, false);
        }
    },
});

/*
 * A component to generate select lists from wing options.
 */

Vue.component('wing-select', {
  template : `<select @change="object.save(property)" class="form-control custom-select" v-model="object.properties[property]">
    <option v-for="option in options()" :value="option">{{_option(option)}}</option>
  </select>`,
  props: ['object','property'],
  methods : {
    options() {
        if ('_options' in this.object.properties) {
            return this.object.properties._options[this.property];
        }
        return [];
    },
    _option(option) {
        return this.object.properties._options['_'+this.property][option];
    },
  },
});

/*
 * A component to count the characters remaining in a text area.
 */

Vue.component('characters-remaining', {
    template : `<small v-bind:class="{'text-danger': toobig, 'text-warning': nearlyfull}" class="text-sm float-right form-text">Characters Remaining: {{remaining}} / {{max}}</small>`,
    props: ['property','max'],
    computed : {
        remaining() {
            if (_.isString(this.property)) {
                return this.max - this.property.length;
            }
            return this.max;
        },
        toobig() {
            return this.remaining <= 0;
        },
        nearlyfull() {
            const fivepercent = this.max * 0.05;
            return this.remaining < fivepercent && this.remaining > 0;
        }
    },
});

/*
 * A button to toggle confirmations.
 */

Vue.component('confirmation-toggle', {
    template : `<button v-if="wing.confirmations.enabled()" class="btn btn-danger" @click="wing.confirmations.toggle()"><i class="fas fa-minus-circle"></i> Disable Confirmations</button>
                <button v-else class="btn btn-secondary" @click="wing.confirmations.toggle()"><i class="fas fa-check-circle"></i> Enable Confirmations</button>`,
});


/*
 * Wing Factories, Services, and Utilities
 */

const wing = {

   /*
    * get a cookie by name
    */

    get_cookie(a) {
         let b = document.cookie.match('(^|;)\\s*' + a + '\\s*=\\s*([^;]+)');
         return b ? b.pop() : '';
    },

    /*
    * scroll the window to an element
    */

    scroll_to (el) {
        var elbox = el.getBoundingClientRect();
        var bodybox = document.body.getBoundingClientRect();
        window.scroll(elbox.left - bodybox.left, elbox.top - bodybox.top);
    },

    /*
     * base URI when you're working against a server that is not on your domain
     */

     base_uri : '',

     format_base_uri : function(uri_suffix) {
         return wing.base_uri + uri_suffix;
     },

     /*
      * format wing options as bootstrap-vue options
      */
     format_field_options : function(wing_options) {
         const bv_options = {};
         for (const field in wing_options) {
             if (!field.startsWith('_')) {
                 bv_options[field] = [];
                 for (const key in wing_options[field]) {
                     const value = wing_options[field][key];
                     bv_options[field].push({
                         value : value,
                         text : wing_options['_'+field][value],
                     });
                 }
             }
         }
         return bv_options;
     },

     /*
      * return field options for a particular field formatted as bootstrap-vue options
      */
     get_field_options : function(field, wing_options) {
         const bv_options = [];
         for (const key in wing_options[field]) {
             const value = wing_options[field][key];
             bv_options.push({
                 value : value,
                 text : wing_options['_'+field][value],
             });
         }
         return bv_options;
     },

    /*
    * Manages the ajax progress bar
    */

    throbber : new Vue({
        el: '#wingajaxprogress',
        data : { counter : 0, max: 100, workers : 0 },
        methods : {
            working () {
                this.counter = 100;
                this.workers++;
            },
            done () {
                const self = this;
                self.workers--;
                if (self.workers < 1) {
                    self.counter = 1;
                    setTimeout(function() {
                        self.counter = 0;
                    }, 200)
                }
            },
        }
    }),

    confirmations : {
        _enabled : true,
        enabled () {
            return wing.confirmations._enabled;
        },
        disabled () {
            return !wing.confirmations._enabled;
        },
        toggle () {
            if (wing.confirmations._enabled == true) {
                if (confirm('Are you sure you want to disable confirmations on deletes?')) {
                    wing.confirmations._enabled = false;
                }
            }
            else {
                wing.confirmations._enabled = true;
            }
        },
    },

    /*
    * Manages a single wing database record via Ajax.
    */

    format_post_data(params) {
        var form = new FormData();
        _.forEach(params, function(value, key) {
            if (typeof(value) == 'object') {
                if (value instanceof File) {
                    form.append(key, value);
                }
                else {
                    _.forEach(value, function(element) {
                        form.append(key, element);
                    });
                }
            }
            else {
                form.append(key, value);
            }
        });
        return form;
    },

    object : (behavior) => ({

        properties : behavior.properties || {},
        params : _.defaultsDeep({}, behavior.params, { _include_relationships : 1}),
        create_api : behavior.create_api,
        fetch_api : behavior.fetch_api,
        _stash : {},

        stash(name,value) {
            const self = this;
            if (typeof(value) !== 'undefined') {
                Vue.set(self._stash, name, value);
            }
            if (name in self._stash) {
                return self._stash[name];
            }
            else {
                return null;
            }
        },

        fetch : function(options) {
            const self = this;
            const fetch_api = (typeof self.properties !== 'undefined' && typeof self.properties._relationships !== 'undefined' && self.properties._relationships.self) || self.fetch_api;
            if (!fetch_api) {
                console.error('wing.object fetch_api is empty');
            }
            const promise = axios({
                method:'get',
                url: wing.format_base_uri(fetch_api),
                params : self.params,
                withCredentials : behavior.with_credentials != null ? behavior.with_credentials : true,
            });
            promise.then(function (response) {
                const data = response.data;
                self.properties = data.result;
                self.id = data.result.id;
                if (typeof options !== 'undefined' && typeof options.on_success !== 'undefined') {
                    options.on_success(data.result);
                }
                if (typeof behavior.on_fetch !== 'undefined') {
                    behavior.on_fetch(data.result);
                }
            })
            .catch( function (error) {
                console.dir(error);
                const data = error.response.data;
                if (typeof options !== 'undefined' && typeof options.on_error !== 'undefined') {
                    options.on_error(data.result);
                }
                if (typeof behavior.on_error !== 'undefined') {
                    behavior.on_error(data.result);
                }
                return self;
            });
            return promise;
        },

        format_field_options : function() {
            return wing.format_field_options(this.properties._options || {});
        },

        get_field_options : function(field) {
            return wing.get_field_options(field, this.properties._options || {});
        },

        create : function(properties, options) {
            const self = this;
            if (!self.create_api) {
                console.error('wing.object create_api is empty');
            }
            const params = wing.format_post_data(_.extend({}, self.params, properties));
            const promise = axios({
                method:'post',
                url: wing.format_base_uri(self.create_api),
                data : params,
                withCredentials : behavior.with_credentials != null ? behavior.with_credentials : true,
            });
            promise.then(function (response) {
                const data = response.data;
                self.properties = data.result;
                self.id = data.result.id;
                if (typeof options !== 'undefined' && typeof options.on_success !== 'undefined') {
                    options.on_success(data.result);
                }
                if (typeof behavior.on_create !== 'undefined') {
                    behavior.on_create(data.result);
                }
            })
            .catch( function (error) {
                console.dir(error);
                const data = error.response.data;
                if (typeof options !== 'undefined' && typeof options.on_error !== 'undefined') {
                    options.on_error(data.result);
                }
                if (typeof behavior.on_error !== 'undefined') {
                    behavior.on_error(data.result);
                }
            });
            return promise;
        },

        update :  function(options) {
            const self = this;
            return self.partial_update(self.properties, options);
        },

        save : _.debounce(function(property) {
            return this._save(property);
        }, 200),

        _save : function(property) {
            const self = this;
            const update = {};
            update[property] = self.properties[property];
            return self._partial_update(update);
        },

        call : function(method, uri, properties, options) {
            const self = this;
            const params = _.extend({}, self.params, properties);
            const config = {
                method: method.toLowerCase(),
                url: wing.format_base_uri(uri),
                params : params,
                withCredentials : behavior.with_credentials != null ? behavior.with_credentials : true,
            };
            if (config.method == 'put' || config.method == 'post') {
                config['data'] = wing.format_post_data(params);
            }
            else {
                config['params'] = params;
            }
            const promise = axios(config);
            promise.then(function (response) {
                const data = response.data;
                self.properties = data.result;
                if (typeof options !== 'undefined' && typeof options.on_success !== 'undefined') {
                    options.on_success(data.result);
                }
            })
            .catch( function (error) {
                console.error('Problem with CALL: '+uri);
                console.dir(error);
                const data = error.response.data;
                if (typeof options !== 'undefined' && typeof options.on_error !== 'undefined') {
                    options.on_error(data.result);
                }
                if (typeof behavior.on_error !== 'undefined') {
                    behavior.on_error(data.result);
                }
            });
            return promise;
        },

        partial_update : _.debounce(function(properties, options) {
            return this._partial_update(properties, options);
        }, 200),

        _partial_update : function(properties, options) {
            const self = this;
            const params = wing.format_post_data(_.extend({}, self.params, properties));
            const promise = axios({
                method: 'put',
                url: wing.format_base_uri(self.properties._relationships.self),
                data : params,
                withCredentials : behavior.with_credentials != null ? behavior.with_credentials : true,
            });
            promise.then(function (response) {
                const data = response.data;
                self.properties = data.result;
                if (typeof options !== 'undefined' && typeof options.on_success !== 'undefined') {
                    options.on_success(data.result);
                }
                if (typeof behavior.on_update !== 'undefined') {
                    behavior.on_update(data.result);
                }
            })
            .catch( function (error) {
                console.error(error);
                const data = error.response.data;
                if (typeof options !== 'undefined' && typeof options.on_error !== 'undefined') {
                    options.on_error(data.result);
                }
                if (typeof behavior.on_error !== 'undefined') {
                    behavior.on_error(data.result);
                }
            });
            return promise;
        },

        delete : function(options) {
            const self = this;
            const object = self.properties;
            if (_.isEmpty(object._relationships.self)) {
                console.error('You need to specify an API URL to use the wing.delete method.');
            }
            let message = 'Are you sure?';
            if ('name' in object) {
                message = 'Are you sure you want to delete ' + object.name + '?';
            }
            if ((typeof options !== 'undefined' && typeof options.skip_confirm !== 'undefined' && options.skip_confirm == true) ||  wing.confirmations.disabled() || confirm(message)) {
                const promise = axios({
                    method: 'delete',
                    url: wing.format_base_uri(object._relationships.self),
                    params : self.params,
                    withCredentials : behavior.with_credentials != null ? behavior.with_credentials : true,
                });
                promise.then(function (response) {
                    const data = response.data;
                    if (typeof options !== 'undefined' && typeof options.on_success !== 'undefined') {
                        options.on_success(object);
                    }
                    if (typeof behavior.on_delete !== 'undefined') {
                        behavior.on_delete(object);
                    }
                    self.properties = {};
                })
                .catch( function (error) {
                    console.dir(error);
                    const data = error.response.data;
                    if (typeof options !== 'undefined' && typeof options.on_error !== 'undefined') {
                        options.on_error(data.error);
                    }
                    if (typeof behavior.on_error !== 'undefined') {
                        behavior.on_error(data.error);
                    }
                });
                return promise;
            }
        },

    }),

    /*
    *   Manages wing lists of objects, like "users" rather than "user"
    */
    object_list : (behavior) => ({

        params : _.defaultsDeep({}, behavior.params, { _include_relationships : 1}),
        objects : [],
        paging : {},
        new : _.defaultsDeep({}, behavior.new_defaults),
        reset_new() { this.new = _.defaultsDeep({}, behavior.new_defaults) },
        list_api : behavior.list_api,
        create_api : behavior.create_api,
        field_options : {},
        items_per_page_options : [
            { value : 5, text : "5 per page" },
            { value : 10, text : "10 per page" },
            { value : 25, text : "25 per page" },
            { value : 50, text : "50 per page" },
            { value : 100, text : "100 per page" },
        ],

        find_object_index : function(id) {
            const self = this;
            for (var i = 0, len = self.objects.length; i < len; i++) {
                if (self.objects[i].properties.id === id) return i;
            }
            return -1;
        },

        find_object : function(id) {
            const self = this;
            const index = self.find_object_index(id);
            if (index == -1) {
                return null;
            }
            return self.objects[index];
        },

        _create_object : function(properties) {
            const self = this;
            return wing.object({
                properties : properties,
                params : self.params,
                create_api : self.create_api,
                on_create : behavior.on_create,
                on_update : behavior.on_update,
                on_delete : function(properties) {
                    const myself = this;
                    self.paging.total_items--;
                    if ('on_delete' in behavior) {
                        behavior.on_delete(properties);
                    }
                    self.remove(properties.id);
                },
            });
        },

        append : function(properties, options) {
            const self = this;
            const new_object = self._create_object(properties);
            self.objects.push(new_object);
            if (typeof options !== 'undefined' && typeof options.on_each !== 'undefined') {
                options.on_each(properties, self.objects[self.objects.length -1]);
            }
            if (typeof behavior.on_each !== 'undefined') {
                behavior.on_each(properties, self.objects[self.objects.length -1]);
            }
            return new_object;
        },

        search : _.debounce(function(options) {
            return this._search(options);
        }, 200),

        _search : function(options) {
            const self = this;
            if (!self.list_api) {
                console.error('wing.object_list list_api is empty');
            }
            let pagination = {
                _page_number : self.paging.page_number || 1,
                _items_per_page : self.paging.items_per_page || 10,
            };
            if (typeof options !== 'undefined' && typeof options.params !== 'undefined') {
                pagination = _.extend({}, pagination, options.params);
            }
            const params = _.extend({}, pagination, self.params);
            const promise = axios({
                method: 'get',
                url: wing.format_base_uri(self.list_api),
                params : params,
                withCredentials : behavior.with_credentials != null ? behavior.with_credentials : true,
            });
            promise.then(function (response) {
                const data = response.data;
                if (typeof options === 'undefined' || typeof options !== 'undefined' && options.accumulate != true) {
                    self.objects = [];
                }
                for (var index = 0; index < data.result.items.length; index++) {
                    self.append(data.result.items[index], options);
                }
                self.paging = data.result.paging;
                const items = data.result.items;
                if (typeof options !== 'undefined' && typeof options.prepend_item !== 'undefined') { // useful for typeahead
                    items.unshift(options.prepend_item);
                }
                if (typeof options !== 'undefined' && typeof options.on_success !== 'undefined') {
                    options.on_success(data.result);
                }
                if (typeof behavior.on_success !== 'undefined') {
                    behavior.on_success(data.result);
                }
                return items;
            })
            .catch(function (error) {console.error(error)});
            return promise;
        },

        all : _.debounce(function(options, page_number) {
            return this._all(options, page_number);
        }, 200),

        _all : function(options, page_number) {
            const self = this;
            if (!self.list_api) {
                console.error('wing.object_list list_api is empty');
            }
            let params = _.extend({}, {
                _page_number: page_number || 1,
                _items_per_page: 10,
            }, self.params);
            if (typeof options !== 'undefined' && typeof options.params !== 'undefined') {
                params = _.extend({}, params, options.params);
            }
            const promise = axios({
                method: 'get',
                url: wing.format_base_uri(self.list_api),
                params : params,
                withCredentials : behavior.with_credentials != null ? behavior.with_credentials : true,
            });
            promise.then(function (response) {
                const data = response.data;
                for (var index in data.result.items) {
                    self.append(data.result.items[index], options);
                }
                if (typeof options !== 'undefined' && typeof options.on_success !== 'undefined') {
                    options.on_success();
                }
                if (typeof behavior.on_success !== 'undefined') {
                    behavior.on_success();
                }
                if (data.result.paging.page_number < data.result.paging.total_pages) {
                    return self._all(options, data.result.paging.next_page_number);
                }
                else {
                    if (typeof options !== 'undefined' && typeof options.on_all_done !== 'undefined') {
                        options.on_all_done();
                    }
                }
            })
            .catch(function (error) {console.error(error)});
            return promise;
        },

        reset : function() {
            const self = this;
            self.objects = [];
            return self;
        },

        call : function(method, uri, properties, options) {
            const self = this;
            const params = _.extend({}, params, self.params, properties);
            const promise = axios({
                method: method.toLowerCase(),
                url: wing.format_base_uri(uri),
                params : params,
                withCredentials : behavior.with_credentials != null ? behavior.with_credentials : true,
            });
            promise.then(function (response) {
                const data = response.data;
                if (typeof options !== 'undefined' && typeof options.on_success !== 'undefined') {
                    options.on_success(data.result);
                }
            })
            .catch(function (error) {
                console.error(error);
                const data = error.response.data;
                if (typeof options !== 'undefined' && typeof options.on_error !== 'undefined') {
                    options.on_error(data.result);
                }
                if (typeof behavior.on_error !== 'undefined') {
                    behavior.on_error(data.result);
                }
            });
            return promise;
        },

        options_api : function() {
            const self = this;
            if (behavior.options_api != null) {
                return behavior.options_api;
            }
            return self.create_api + '/_options';
        },

        fetch_options : function(options) {
            const self = this;
            const promise = axios({
                method: 'get',
                url: wing.format_base_uri(self.options_api()),
                withCredentials : behavior.with_credentials != null ? behavior.with_credentials : true,
            });
            promise.then(function (response) {
                const data = response.data;
                self.field_options = data.result;
                if (typeof options !== 'undefined' && typeof options.on_success !== 'undefined') {
                    options.on_success(data.result);
                }
            })
            .catch(function (error) {
                console.error(error);
                const data = error.response.data;
                if (typeof options !== 'undefined' && typeof options.on_error !== 'undefined') {
                    options.on_error(data.result);
                }
            });
            return promise;
        },

        format_field_options : function() {
            return wing.format_field_options(this.field_options || {});
        },

        get_field_options : function(field) {
            return wing.get_field_options(field, this.field_options || {});
        },

        format_objects_as_field_options : function(text_field) {
            const self = this;
            const bv_options = [];
            for (const key in self.objects) {
                bv_options.push({
                    text : self.objects[key].properties[text_field],
                    value : self.objects[key].properties.id,
                });
            }
            return bv_options;
        },

        create : function(new_properties, options) {
            const self = this;
            if (!self.create_api) {
                console.error('wing.object_list create_api is empty');
            }
            let properties = new_properties;
            if (typeof properties === 'undefined') {
                properties = self.new;
            }
            const new_object = self._create_object(properties);
            const add_it = function() {
                if ((typeof options !== 'undefined' && typeof options.unshift !== 'undefined' && options.unshift == true) || (typeof behavior.unshift_on_create !== 'undefined' && behavior.unshift_on_create)) {
                    self.objects.unshift(new_object);
                }
                else {
                    self.objects.push(new_object);
                }
                self.paging.total_items++;
                self.reset_new();
            };
            if (typeof options !== 'undefined') {
                if (typeof options.on_success !== 'undefined') {
                    const success = options.on_success;
                    options.on_success = function(properties) {
                        add_it();
                        success(properties, new_object);
                    };
                }
                else {
                    options['on_success'] = add_it;
                }
            }
            else {
                options = {on_success : add_it};
            }
            return new_object.create(properties, options);
        },

        update : function(index, options) {
            const self = this;
            return self.objects[index].update(options);
        },

        save : function(index, property) {
            const self = this;
            return self.objects[index].save(property);
        },

        partial_update : function(index, properties, options) {
            const self = this;
            return self.objects[index].partial_update(properties, options);
        },

        delete : function(index, options) {
            const self = this;
            return self.objects[index].delete(options);
        },

        remove : function(id) {
            const self = this;
            const index = self.find_object_index(id);
            if (index >= 0) {
                self.objects.splice(index, 1);
            }
        }

    }),

    /*
    * display an error message
    */

    error : (message) => {
        const n = new Noty({
            text: message,
            theme : 'bootstrap-v4',
            type: 'error',
            layout: 'center',
            timeout : 15000,
        }).show();
    },

    /*
    * display a success message
    */

    success : (message) => {
        new Noty({
            text: message,
            theme : 'bootstrap-v4',
            type: 'success',
            layout: 'bottomLeft',
            timeout : 8000,
        }).show();
    },

    /*
    * display a warning
    */

    warn : (message) => {
        new Noty({
            text: message,
            theme : 'bootstrap-v4',
            type: 'warning',
            layout: 'bottomLeft',
            timeout : 8000,
        }).show();
    },

    /*
    * display some info
    */

    info : (message) => {
        new Noty({
            text: message,
            theme : 'bootstrap-v4',
            type: 'info',
            layout: 'bottomLeft',
            timeout : 8000,
        }).show();
    },

    /*
    * generate a random string
    */

    string_random : (length) => {
        var text = "";
        if (!length) {
            length = 6;
        }
        var possible = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
        for ( var i=0; i < length; i++ )
            text += possible.charAt(Math.floor(Math.random() * possible.length));
        return text;
    },

    /*
     * parses a date into a moment object
     */

     parse_date : (input, timezone) => {
         if (typeof moment === 'undefined') {
             wing.error('moment.js not installed');
             return input;
         }
         else {
             if (Array.isArray(input) && typeof input[0] === 'string') {  // date + input pattern
                 date = moment(input[0], input[1], true);
             }
             else if (typeof input === 'string' && input.length == 19) { // mysql datetime
                 var parts = input.split(/\s/);
                 var string = parts[0]+'T'+parts[1]+'+00:00'; // wing dates are UTC
                 date = moment(string);
             }
             else if (typeof input === 'string' && input.length == 10) { // mysql date
                 date = moment(input, 'YYYY-MM-DD', true);
             }
             else if (input instanceof moment) {
                 date = input;
             }
             else if (typeof input === 'number' && input > 1000000000000) { // milliseconds since epoch
                 date = moment(input);
             }
             else if (typeof input === 'number') { // seconds since epoch
                 date = moment.unix(input);
             }
             else { // must be a normal date
                 date = moment(input);
             }
             if (typeof moment.tz === 'function' && _.isString(timezone)) {
                date = date.tz(timezone);
             }
             return date;
         }
     },

     get_query_param(name, url) {
         if (!url) url = window.location.href;
         name = name.replace(/[\[\]]/g, "\\$&");
         var regex = new RegExp("[?&]" + name + "(=([^&#]*)|&|#|$)"),
             results = regex.exec(url);
         if (!results) return null;
         if (!results[2]) return '';
         return decodeURIComponent(results[2].replace(/\+/g, " "));
     },

     firebase(user_id) {
         if (typeof firebase === 'undefined') {
             wing.error('Firebase client not installed');
             return null;
         }
         else {
             const promise = axios.get('/api/user/'+user_id+'/firebase-jwt').
             then(function(response) {
                 const config = response.data.result;
                 firebase.initializeApp({
                     databaseURL : 'https://'+config.database+'.firebaseio.com',
                     apiKey : config.api_key,
                     authDomain : config.id+'.firebaseapp.com',
                 });
                 firebase.auth().signInWithCustomToken(config.jwt).catch(function(error) {
                     console.log("Firebase login failed!", error);
                 });
                 firebase.database().ref('/status/'+user_id).on('child_added', function(snapshot) {
                     const message = snapshot.val();
                     if (_.includes(['warn','info','error','success'], message.type)) {
                         wing[message.type](message.message);
                         setTimeout(function(){ snapshot.ref.remove(); }, 1000);
                     }
                     else {
                         console.dir(message);
                     }
                 });
             });
         }
     },

};

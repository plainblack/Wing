/*
 * A component to generate select lists from wing options.
 */

Vue.component('wing-select', {
  template : `<select @change="object.save(property)" class="form-control" v-model="object.properties[property]">
    <option v-for="option in options()" :value="option">{{_option(option)}}</option>
  </select>`,
  props: ['object','property'],
  methods : {
    options : function() {
        if ('_options' in this.object.properties) {
            return this.object.properties._options[this.property];
        }
        return [];
    },
    _option: function(option) {
        return this.object.properties._options['_'+this.property][option];
    },
  },
});

/*
 * A component to generate select lists from wing options.
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
 * Throbber progress bar element
 */

var throbber = document.createElement('div');
throbber.innerHTML = `<div id="wingajaxprogress" style="z-index: 10000; position: fixed; top: 0px; width: 100%;">
    <template v-if="counter > 0"><b-progress :value="counter" :max="max" height="5px" animated></b-progress></template>
</div>`;
document.body.appendChild(throbber);


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
        }
    }
    return response;
}, function (error) {
    wing.throbber.done();
    var message = 'Error communicating with server.';
    if (error.response.headers['content-type'] === "application/json; charset=utf-8" && "error" in error.response.data) {
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
    wing.error(message);
    return Promise.reject(error);
});

/*
 * Wing Factories and Utilities
 */

const wing = {

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
                    }, 500)
                }
            },
        }
    }),

    /*
    * Manages a single wing database record via Ajax.
    */

    new_object_manager : (behavior) => ({

        id : typeof behavior.properties !== 'undefined' ? behavior.properties.id : null,
        properties : behavior.properties || {},
        params : _.defaultsDeep({}, behavior.params, { _include_relationships : 1}),

        fetch : function(options) {
            const self = this;
            const promise = axios({
                method:'get',
                url: (typeof self.properties !== 'undefined' && typeof self.properties._relationships !== 'undefined' && self.properties._relationships.self) || behavior.fetch_api,
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

        create : function(properties, options) {
            const self = this;
            const params = _.extend({}, self.params, properties);
            const promise = axios({
                method:'post',
                url: behavior.create_api,
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

        save : function(property) {
            const self = this;
            const update = {};
            update[property] = self.properties[property];
            return self.partial_update(update);
        },

        call : function(method, uri, properties, options) {
            const self = this;
            const params = _.extend({}, self.params, properties);
            const config = {
                method: method.toLowerCase(),
                url: uri,
                params : params,
                withCredentials : behavior.with_credentials != null ? behavior.with_credentials : true,
            };
            if (config.method == 'put' || config.method == 'post') {
                config[data] = params;
            }
            else {
                config[params] = params;
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
            const params = _.extend({}, self.params, properties);
            const promise = axios({
                method: 'put',
                url: self.properties._relationships.self,
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
            let message = 'Are you sure?';
            if ('name' in object) {
                message = 'Are you sure you want to delete ' + object.name + '?';
            }
            if ((typeof options !== 'undefined' && typeof options.skip_confirm !== 'undefined' && options.skip_confirm == true) || confirm(message)) {
                const promise = axios({
                    method: 'delete',
                    url: object._relationships.self,
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
                        options.on_error(data.result);
                    }
                    if (typeof behavior.on_error !== 'undefined') {
                        behavior.on_error(data.result);
                    }
                });
                return promise;
            }
        },

    }),

    /*
    *   Manages wing lists of objects, like "users" rather than "user"
    */
    new_object_list_manager : (behavior) => ({

        params : _.defaultsDeep({}, behavior.params, { _include_relationships : 1}),
        objects : [],
        paging : {},
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

        _create_object_manager : function(properties) {
            const self = this;
            return wing.new_object_manager({
                properties : properties,
                params : self.params,
                create_api : behavior.create_api,
                on_create : behavior.on_create,
                on_update : behavior.on_update,
                on_delete : function(properties) {
                    const myself = this;
                    if ('on_delete' in behavior) {
                        behavior.on_delete(properties);
                    }
                    const index = self.find_object_index(properties.id);
                    if (index >= 0) {
                        self.objects.splice(index, 1);
                    }
                },
            });
        },

        search : _.debounce(function(options) {
            return this._search(options);
        }, 200),

        _search : function(options) {
            const self = this;
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
                url: behavior.list_api,
                params : params,
                withCredentials : behavior.with_credentials != null ? behavior.with_credentials : true,
            });
            promise.then(function (response) {
                const data = response.data;
                if (typeof options === 'undefined' || typeof options !== 'undefined' && options.accumulate != true) {
                    self.objects = [];
                }
                for (var index = 0; index < data.result.items.length; index++) {
                    self.objects.push(self._create_object_manager(data.result.items[index]));
                    if (typeof options !== 'undefined' && typeof options.on_each !== 'undefined') {
                        options.on_each(data.result.items[index], self.objects[self.objects.length -1]);
                    }
                    if (typeof behavior.on_each !== 'undefined') {
                        behavior.on_each(data.result.items[index], self.objects[self.objects.length -1]);
                    }
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
            .catch(function (error) {});
            return promise;
        },

        all : _.debounce(function(options, page_number) {
            return this._all(options, page_number);
        }, 200),

        _all : function(options, page_number) {
            const self = this;
            let params = _.extend({}, {
                _page_number: page_number || 1,
                _items_per_page: 10,
            }, self.params);
            if (typeof options !== 'undefined' && typeof options.params !== 'undefined') {
                params = _.extend({}, params, options.params);
            }
            const promise = axios({
                method: 'get',
                url: behavior.list_api,
                params : params,
                withCredentials : behavior.with_credentials != null ? behavior.with_credentials : true,
            });
            promise.then(function (response) {
                const data = response.data;
                for (var index in data.result.items) {
                    self.objects.push(self._create_object_manager(data.result.items[index]));
                    if (typeof options !== 'undefined' && typeof options.on_each !== 'undefined') {
                        options.on_each(data.result.items[index], self.objects[self.objects.length -1]);
                    }
                    if (typeof behavior.on_each !== 'undefined') {
                        behavior.on_each(data.result.items[index], self.objects[self.objects.length -1]);
                    }
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
            .catch(function (error) {});
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
                url: uri,
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
            if (behavior.options_api != null) {
                return behavior.options_api;
            }
            return behavior.create_api + '/_options';
        },

        fetch_options : function(store_data_here, options) {
            const self = this;
            const promise = axios({
                method: 'get',
                url: self.options_api(),
                params : params,
                withCredentials : behavior.with_credentials != null ? behavior.with_credentials : true,
            });
            promise.then(function (response) {
                const data = response.data;
                for(var key in data.result) {
                    store_data_here[key] = data.result[key];
                }
                if (typeof options !== 'undefined' && typeof options.on_success !== 'undefined') {
                    options.on_success(data.result);
                }
            })
            .catch(function (error) {
                const data = error.response.data;
                if (typeof options !== 'undefined' && typeof options.on_error !== 'undefined') {
                    options.on_error(data.result);
                }
            });
            return promise;
        },

        create : function(properties, options) {
            const self = this;
            const new_object = self._create_object_manager(properties);
            const add_it = function() {
                if (typeof options !== 'undefined' && typeof options.unshift !== 'undefined' && options.unshift == true) {
                    self.objects.unshift(new_object);
                }
                else {
                    self.objects.push(new_object);
                }
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

};

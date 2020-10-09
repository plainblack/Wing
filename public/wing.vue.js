/*
 * Axios global settings
 */

// send session cookie
axios.defaults.withCredentials = true;
//disable IE ajax request caching
axios.defaults.headers.get["If-Modified-Since"] =
  "Mon, 26 Jul 1997 05:00:00 GMT";
//more cache control
axios.defaults.headers.get["Cache-Control"] = "no-cache";
axios.defaults.headers.get["Pragma"] = "no-cache";
axios.defaults.paramsSerializer = function (params) {
  return Qs.stringify(params, { arrayFormat: "repeat" });
};
axios.interceptors.request.use(
  function (config) {
    wing.throbber.working();
    return config;
  },
  function (error) {
    wing.throbber.done();
    return Promise.reject(error);
  }
);
axios.interceptors.response.use(
  function (response) {
    wing.throbber.done();
    if (
      response.headers["content-type"] === "application/json; charset=utf-8" &&
      "_warnings" in response.data.result
    ) {
      for (var warning in response.data.result._warnings) {
        document.dispatchEvent(
          new CustomEvent("wing_warn", {
            message: response.data.result._warnings[warning].message,
          })
        );
        wing.warn(response.data.result._warnings[warning].message);
      }
    }
    return response;
  },
  function (error) {
    wing.throbber.done();
    var message = "Error communicating with server.";
    if (
      _.isObject(error.response) &&
      _.isObject(error.response.headers) &&
      error.response.headers["content-type"] ===
        "application/json; charset=utf-8" &&
      "error" in error.response.data
    ) {
      if (error.response.data.error.code == 401) {
        var message = [
          "div",
          {},
          [
            "You must ",
            [
              "a",
              { attrs: { href: "/account" }, class: "btn btn-primary btn-sm" },
              "log in",
            ],
            " to do that.",
          ],
        ];
      } else {
        message = error.response.data.error.message;
        var matches = message.split(/ /);
        var field = matches[0].toLowerCase();
        var nodelist = document.querySelectorAll('label[for="' + field + '"]');
        if (nodelist.length > 0) {
          var label = nodelist[0].innerText;
          if (label) {
            message = message.replace(field, label);
          }
        }
      }
    }
    document.dispatchEvent(new CustomEvent("wing_error", { message: message }));
    wing.error(message);
    return Promise.reject(error);
  }
);

/*
 * Throbber progress bar element
 */

var throbber = document.createElement("div");
throbber.innerHTML = `<div id="wingajaxprogress" style="z-index: 10000; position: fixed; top: 0px; width: 100%;">
    <template v-if="counter > 0"><b-progress :value="counter" :max="max" height="10px" animated></b-progress></template>
</div>`;
document.body.appendChild(throbber);

/*
 * Toast element used for rendering system messages. See wing.info, wing.success, wing.error, and wing.warn.
 */

var toastdiv = document.createElement("div");
toastdiv.id = "wingtoast";
document.body.appendChild(toastdiv);

/*
 * Wing Factories, Services, and Utilities
 */

const wing = {
  /*
   * get a cookie by name
   */

  get_cookie(a) {
    let b = document.cookie.match("(^|;)\\s*" + a + "\\s*=\\s*([^;]+)");
    return b ? b.pop() : "";
  },

  generate_id() {
    return "_" + Math.random().toString(36).substr(2, 9);
  },

  /*
   * scroll the window to an element
   */

  scroll_to(el) {
    var elbox = el.getBoundingClientRect();
    var bodybox = document.body.getBoundingClientRect();
    console.dir([elbox, bodybox]);
    window.scroll(elbox.left - bodybox.left, elbox.top - bodybox.top);
  },

  /*
   * sort numeric items naturally within alpha numeric characters
   */
  natural_sort(a, b) {
    return a.name.localeCompare(b.name, undefined, {
      numeric: true,
      sensitivity: "base",
    });
  },

  /*
   * base URI when you're working against a server that is not on your domain
   */

  base_uri: "",

  format_base_uri: function (uri_suffix) {
    return wing.base_uri + uri_suffix;
  },

  /*
   * format a field name into a field label when you need an automatic one
   */
  format_field_label: function (field_name) {
    return field_name.replace(/_/gm, " ").replace(/\w\S*/g, function (txt) {
      return txt.charAt(0).toUpperCase() + txt.substr(1).toLowerCase();
    });
  },

  /*
   * format wing options as bootstrap-vue options
   */
  format_field_options: function (wing_options) {
    const bv_options = {};
    for (const field in wing_options) {
      if (!field.startsWith("_")) {
        bv_options[field] = [];
        for (const key in wing_options[field]) {
          const value = wing_options[field][key];
          bv_options[field].push({
            value: value,
            text: wing_options["_" + field][value],
          });
        }
      }
    }
    return bv_options;
  },

  /*
   * return field options for a particular field formatted as bootstrap-vue options
   */
  get_field_options: function (field, wing_options) {
    const bv_options = [];
    for (const key in wing_options[field]) {
      const value = wing_options[field][key];
      bv_options.push({
        value: value,
        text: wing_options["_" + field][value],
      });
    }
    return bv_options;
  },

  /*
   * Manages the ajax progress bar
   */

  throbber: new Vue({
    el: "#wingajaxprogress",
    data: { counter: 0, max: 100, workers: 0 },
    methods: {
      working() {
        this.counter = 100;
        this.workers++;
      },
      done() {
        const self = this;
        self.workers--;
        if (self.workers < 1) {
          self.counter = 1;
          setTimeout(function () {
            self.counter = 0;
          }, 200);
        }
      },
    },
  }),

  confirmations: {
    _enabled: true,
    enabled() {
      return wing.confirmations._enabled;
    },
    disabled() {
      return !wing.confirmations._enabled;
    },
    toggle() {
      if (wing.confirmations._enabled == true) {
        if (
          confirm("Are you sure you want to disable confirmations on deletes?")
        ) {
          wing.confirmations._enabled = false;
        }
      } else {
        wing.confirmations._enabled = true;
      }
    },
  },

  /*
   * Manages a single wing database record via Ajax.
   */

  format_post_data(params) {
    var form = new FormData();
    _.forEach(params, function (value, key) {
      //console.log('--'+key+'--');
      //console.dir(value)
      if (typeof value == "object") {
        if (value instanceof File) {
          // handle file upload
          //console.log(key+' is a file');
          form.append(key, value);
        } else if (value == null) {
          // handle null
          //console.log(key+' is null');
          // skip it
        } else if (Array.isArray(value) && typeof value[0] == "object") {
          // handle an array of objects as JSON
          //console.log(key+' is an array of objects');
          form.append(key, JSON.stringify(value));
        } else if (Array.isArray(value)) {
          // handle an array of values as individual key value pairs
          //console.log(key+' is an array of key value pairs');
          _.forEach(value, function (element) {
            form.append(key, element);
          });
        } else {
          // just a normal object hash
          //console.log(key+' is an object hash');
          form.append(key, JSON.stringify(value));
        }
      } else {
        // handle values
        //console.log(key+' is an normal value');
        form.append(key, value);
      }
    });
    return form;
  },

  object: (behavior) => ({
    properties: behavior.properties || {},
    params: _.defaultsDeep({}, behavior.params, { _include_relationships: 1 }),
    create_api: behavior.create_api,
    fetch_api: behavior.fetch_api,
    _stash: {},

    stash(name, value) {
      const self = this;
      if (typeof value !== "undefined") {
        Vue.set(self._stash, name, value);
      }
      if (name in self._stash) {
        return self._stash[name];
      } else {
        return null;
      }
    },

    set_fetch_api(new_uri) {
      this.fetch_api = new_uri;
      if (
        typeof self.properties !== "undefined" &&
        typeof self.properties._relationships !== "undefined"
      ) {
        this.properties._relationships.self = new_uri;
      }
    },

    fetch: function (options) {
      const self = this;
      const fetch_api =
        (typeof self.properties !== "undefined" &&
          typeof self.properties._relationships !== "undefined" &&
          self.properties._relationships.self) ||
        self.fetch_api;
      if (!fetch_api) {
        console.error("wing.object fetch_api is empty");
      }
      const promise = axios({
        method: "get",
        url: wing.format_base_uri(fetch_api),
        params: self.params,
        withCredentials:
          behavior.with_credentials != null ? behavior.with_credentials : true,
      });
      promise
        .then(function (response) {
          const data = response.data;
          self.properties = data.result;
          self.id = data.result.id;
          if (
            typeof options !== "undefined" &&
            typeof options.on_success !== "undefined"
          ) {
            options.on_success(data.result);
          }
          if (typeof behavior.on_fetch !== "undefined") {
            behavior.on_fetch(data.result);
          }
        })
        .catch(function (error) {
          console.dir(error);
          const data = error.response.data;
          if (
            typeof options !== "undefined" &&
            typeof options.on_error !== "undefined"
          ) {
            options.on_error(data.result);
          }
          if (typeof behavior.on_error !== "undefined") {
            behavior.on_error(data.result);
          }
          return self;
        });
      return promise;
    },

    format_field_options: function () {
      return wing.format_field_options(this.properties._options || {});
    },

    get_field_options: function (field) {
      return wing.get_field_options(field, this.properties._options || {});
    },

    create: function (properties, options) {
      const self = this;
      if (!self.create_api) {
        console.error("wing.object create_api is empty");
      }
      const params = wing.format_post_data(
        _.extend({}, self.params, properties)
      );
      const promise = axios({
        method: "post",
        url: wing.format_base_uri(self.create_api),
        data: params,
        withCredentials:
          behavior.with_credentials != null ? behavior.with_credentials : true,
      });
      promise
        .then(function (response) {
          const data = response.data;
          self.properties = data.result;
          self.id = data.result.id;
          if (
            typeof options !== "undefined" &&
            typeof options.on_success !== "undefined"
          ) {
            options.on_success(data.result);
          }
          if (typeof behavior.on_create !== "undefined") {
            behavior.on_create(data.result);
          }
        })
        .catch(function (error) {
          console.dir(error);
          const data = error.response.data;
          if (
            typeof options !== "undefined" &&
            typeof options.on_error !== "undefined"
          ) {
            options.on_error(data.result);
          }
          if (typeof behavior.on_error !== "undefined") {
            behavior.on_error(data.result);
          }
        });
      return promise;
    },

    update: function (options) {
      const self = this;
      return self.partial_update(self.properties, options);
    },

    save: _.debounce(function (property, value) {
      return this._save(property, value);
    }, 200),

    _save: function (property, value) {
      const self = this;
      const update = {};
      update[property] = value || self.properties[property];
      return self._partial_update(update);
    },

    call: function (method, uri, properties, options) {
      const self = this;
      const params = _.extend({}, self.params, properties);
      const config = {
        method: method.toLowerCase(),
        url: wing.format_base_uri(uri),
        params: params,
        withCredentials:
          behavior.with_credentials != null ? behavior.with_credentials : true,
      };
      if (config.method == "put" || config.method == "post") {
        config["data"] = wing.format_post_data(params);
      } else {
        config["params"] = params;
      }
      const promise = axios(config);
      promise
        .then(function (response) {
          const data = response.data;
          self.properties = data.result;
          if (
            typeof options !== "undefined" &&
            typeof options.on_success !== "undefined"
          ) {
            options.on_success(data.result);
          }
        })
        .catch(function (error) {
          console.error("Problem with CALL: " + uri);
          console.dir(error);
          const data = error.response.data;
          if (
            typeof options !== "undefined" &&
            typeof options.on_error !== "undefined"
          ) {
            options.on_error(data.result);
          }
          if (typeof behavior.on_error !== "undefined") {
            behavior.on_error(data.result);
          }
        });
      return promise;
    },

    partial_update: _.debounce(function (properties, options) {
      return this._partial_update(properties, options);
    }, 200),

    _partial_update: function (properties, options) {
      const self = this;
      const params = wing.format_post_data(
        _.extend({}, self.params, properties)
      );
      const promise = axios({
        method: "put",
        url: wing.format_base_uri(self.properties._relationships.self),
        data: params,
        withCredentials:
          behavior.with_credentials != null ? behavior.with_credentials : true,
      });
      promise
        .then(function (response) {
          const data = response.data;
          self.properties = data.result;
          if (
            typeof options !== "undefined" &&
            typeof options.on_success !== "undefined"
          ) {
            options.on_success(data.result);
          }
          if (typeof behavior.on_update !== "undefined") {
            behavior.on_update(data.result);
          }
        })
        .catch(function (error) {
          console.error(error);
          const data = error.response.data;
          if (
            typeof options !== "undefined" &&
            typeof options.on_error !== "undefined"
          ) {
            options.on_error(data.result);
          }
          if (typeof behavior.on_error !== "undefined") {
            behavior.on_error(data.result);
          }
        });
      return promise;
    },

    delete: function (options) {
      const self = this;
      const object = self.properties;
      if (_.isEmpty(object._relationships.self)) {
        console.error(
          "You need to specify an API URL to use the wing.delete method."
        );
      }
      let message = "Are you sure?";
      if ("name" in object) {
        message = "Are you sure you want to delete " + object.name + "?";
      }
      if (
        (typeof options !== "undefined" &&
          typeof options.skip_confirm !== "undefined" &&
          options.skip_confirm == true) ||
        wing.confirmations.disabled() ||
        confirm(message)
      ) {
        const promise = axios({
          method: "delete",
          url: wing.format_base_uri(object._relationships.self),
          params: self.params,
          withCredentials:
            behavior.with_credentials != null
              ? behavior.with_credentials
              : true,
        });
        promise
          .then(function (response) {
            const data = response.data;
            if (
              typeof options !== "undefined" &&
              typeof options.on_success !== "undefined"
            ) {
              options.on_success(object);
            }
            if (typeof behavior.on_delete !== "undefined") {
              behavior.on_delete(object);
            }
            self.properties = {};
          })
          .catch(function (error) {
            console.dir(error);
            const data = error.response.data;
            if (
              typeof options !== "undefined" &&
              typeof options.on_error !== "undefined"
            ) {
              options.on_error(data.error);
            }
            if (typeof behavior.on_error !== "undefined") {
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
  object_list: (behavior) => ({
    params: _.defaultsDeep({}, behavior.params, { _include_relationships: 1 }),
    search_params: _.defaultsDeep({}, behavior.search_params, {
      _include_relationships: 1,
    }),
    objects: [],
    paging: {},
    new: _.defaultsDeep({}, behavior.new_defaults),
    reset_new() {
      this.new = _.defaultsDeep({}, behavior.new_defaults);
    },
    list_api: behavior.list_api,
    create_api: behavior.create_api,
    field_options: {},
    items_per_page_options: [
      { value: 5, text: "5 per page" },
      { value: 10, text: "10 per page" },
      { value: 25, text: "25 per page" },
      { value: 50, text: "50 per page" },
      { value: 100, text: "100 per page" },
    ],

    find_object_index: function (id) {
      const self = this;
      for (var i = 0, len = self.objects.length; i < len; i++) {
        if (self.objects[i].properties.id === id) return i;
      }
      return -1;
    },

    find_object: function (id) {
      const self = this;
      const index = self.find_object_index(id);
      if (index == -1) {
        return null;
      }
      return self.objects[index];
    },

    _create_object: function (properties) {
      const self = this;
      return wing.object({
        properties: properties,
        params: self.params,
        create_api: self.create_api,
        on_create: behavior.on_create,
        on_update: behavior.on_update,
        on_delete: function (properties) {
          const myself = this;
          self.paging.total_items--;
          if ("on_delete" in behavior) {
            behavior.on_delete(properties);
          }
          self.remove(properties.id);
        },
      });
    },

    append: function (properties, options) {
      const self = this;
      const new_object = self._create_object(properties);
      self.objects.push(new_object);
      if (
        typeof options !== "undefined" &&
        typeof options.on_each !== "undefined"
      ) {
        options.on_each(properties, self.objects[self.objects.length - 1]);
      }
      if (typeof behavior.on_each !== "undefined") {
        behavior.on_each(properties, self.objects[self.objects.length - 1]);
      }
      return new_object;
    },

    search: _.debounce(function (options) {
      return this._search(options);
    }, 500),

    search_fast: _.debounce(function (options) {
      return this._search(options);
    }, 200),

    _search: function (options) {
      const self = this;
      if (!self.list_api) {
        console.error("wing.object_list list_api is empty");
      }
      let pagination = {
        _page_number: self.paging.page_number || 1,
        _items_per_page: self.paging.items_per_page || 10,
      };
      if (
        typeof options !== "undefined" &&
        typeof options.params !== "undefined"
      ) {
        pagination = _.extend({}, pagination, options.params);
      }
      const params = _.extend({}, pagination, self.params, self.search_params);
      const promise = axios({
        method: "get",
        url: wing.format_base_uri(self.list_api),
        params: params,
        withCredentials:
          behavior.with_credentials != null ? behavior.with_credentials : true,
      });
      promise
        .then(function (response) {
          const data = response.data;
          if (
            typeof options === "undefined" ||
            (typeof options !== "undefined" && options.accumulate != true)
          ) {
            self.objects = [];
          }
          for (var index = 0; index < data.result.items.length; index++) {
            self.append(data.result.items[index], options);
          }
          self.paging = data.result.paging;
          const items = data.result.items;
          if (
            typeof options !== "undefined" &&
            typeof options.prepend_item !== "undefined"
          ) {
            // useful for typeahead
            items.unshift(options.prepend_item);
          }
          if (
            typeof options !== "undefined" &&
            typeof options.on_success !== "undefined"
          ) {
            options.on_success(data.result);
          }
          if (typeof behavior.on_success !== "undefined") {
            behavior.on_success(data.result);
          }
          return items;
        })
        .catch(function (error) {
          console.error(error);
        });
      return promise;
    },

    all: _.debounce(function (options, page_number) {
      return this._all(options, page_number);
    }, 200),

    _all: function (options, page_number) {
      const self = this;
      if (!self.list_api) {
        console.error("wing.object_list list_api is empty");
      }
      let params = _.extend(
        {},
        {
          _page_number: page_number || 1,
          _items_per_page: 10,
        },
        self.params,
        self.search_params
      );
      if (
        typeof options !== "undefined" &&
        typeof options.params !== "undefined"
      ) {
        params = _.extend({}, params, options.params);
      }
      const promise = axios({
        method: "get",
        url: wing.format_base_uri(self.list_api),
        params: params,
        withCredentials:
          behavior.with_credentials != null ? behavior.with_credentials : true,
      });
      promise
        .then(function (response) {
          const data = response.data;
          for (var index in data.result.items) {
            self.append(data.result.items[index], options);
          }
          if (
            typeof options !== "undefined" &&
            typeof options.on_success !== "undefined"
          ) {
            options.on_success();
          }
          if (typeof behavior.on_success !== "undefined") {
            behavior.on_success();
          }
          if (data.result.paging.page_number < data.result.paging.total_pages) {
            return self._all(options, data.result.paging.next_page_number);
          } else {
            if (
              typeof options !== "undefined" &&
              typeof options.on_all_done !== "undefined"
            ) {
              options.on_all_done();
            }
          }
        })
        .catch(function (error) {
          console.error(error);
        });
      return promise;
    },

    reset: function () {
      const self = this;
      self.objects = [];
      return self;
    },

    call: function (method, uri, properties, options) {
      const self = this;
      const params = _.extend({}, self.params, properties);
      const promise = axios({
        method: method.toLowerCase(),
        url: wing.format_base_uri(uri),
        params: params,
        withCredentials:
          behavior.with_credentials != null ? behavior.with_credentials : true,
      });
      promise
        .then(function (response) {
          const data = response.data;
          if (
            typeof options !== "undefined" &&
            typeof options.on_success !== "undefined"
          ) {
            options.on_success(data.result);
          }
        })
        .catch(function (error) {
          console.error(error);
          const data = error.response.data;
          if (
            typeof options !== "undefined" &&
            typeof options.on_error !== "undefined"
          ) {
            options.on_error(data.result);
          }
          if (typeof behavior.on_error !== "undefined") {
            behavior.on_error(data.result);
          }
        });
      return promise;
    },

    options_api: function () {
      const self = this;
      if (behavior.options_api != null) {
        return behavior.options_api;
      }
      return self.create_api + "/_options";
    },

    fetch_options: function (options) {
      const self = this;
      const promise = axios({
        method: "get",
        url: wing.format_base_uri(self.options_api()),
        withCredentials:
          behavior.with_credentials != null ? behavior.with_credentials : true,
      });
      promise
        .then(function (response) {
          const data = response.data;
          self.field_options = data.result;
          if (
            typeof options !== "undefined" &&
            typeof options.on_success !== "undefined"
          ) {
            options.on_success(data.result);
          }
        })
        .catch(function (error) {
          console.error(error);
          const data = error.response.data;
          if (
            typeof options !== "undefined" &&
            typeof options.on_error !== "undefined"
          ) {
            options.on_error(data.result);
          }
        });
      return promise;
    },

    format_field_options: function () {
      return wing.format_field_options(this.field_options || {});
    },

    get_field_options: function (field) {
      return wing.get_field_options(field, this.field_options || {});
    },

    format_objects_as_field_options: function (text_field) {
      const self = this;
      const bv_options = [];
      for (const key in self.objects) {
        bv_options.push({
          text: self.objects[key].properties[text_field],
          value: self.objects[key].properties.id,
        });
      }
      return bv_options;
    },

    create: function (new_properties, options) {
      const self = this;
      if (!self.create_api) {
        console.error("wing.object_list create_api is empty");
      }
      let properties = new_properties;
      if (typeof properties === "undefined") {
        properties = self.new;
      }
      const new_object = self._create_object(properties);
      const add_it = function () {
        if (
          (typeof options !== "undefined" &&
            typeof options.unshift !== "undefined" &&
            options.unshift == true) ||
          (typeof behavior.unshift_on_create !== "undefined" &&
            behavior.unshift_on_create)
        ) {
          self.objects.unshift(new_object);
        } else {
          self.objects.push(new_object);
        }
        self.paging.total_items++;
        self.reset_new();
      };
      if (typeof options !== "undefined") {
        if (typeof options.on_success !== "undefined") {
          const success = options.on_success;
          options.on_success = function (properties) {
            add_it();
            success(properties, new_object);
          };
        } else {
          options["on_success"] = add_it;
        }
      } else {
        options = { on_success: add_it };
      }
      return new_object.create(properties, options);
    },

    update: function (index, options) {
      const self = this;
      return self.objects[index].update(options);
    },

    save: function (index, property) {
      const self = this;
      return self.objects[index].save(property);
    },

    partial_update: function (index, properties, options) {
      const self = this;
      return self.objects[index].partial_update(properties, options);
    },

    delete: function (index, options) {
      const self = this;
      return self.objects[index].delete(options);
    },

    remove: function (id) {
      const self = this;
      const index = self.find_object_index(id);
      if (index >= 0) {
        self.objects.splice(index, 1);
      }
    },
  }),

  /*
   * copy to clipboard - https://hackernoon.com/copying-text-to-clipboard-with-javascript-df4d4988697f
   */

  copy_to_clipboard(str) {
    const el = document.createElement("textarea"); // Create a <textarea> element
    el.value = str; // Set its value to the string that you want copied
    el.setAttribute("readonly", ""); // Make it readonly to be tamper-proof
    el.style.position = "absolute";
    el.style.left = "-9999px"; // Move outside the screen to make it invisible
    document.body.appendChild(el); // Append the <textarea> element to the HTML document
    const selected =
      document.getSelection().rangeCount > 0 // Check if there is any content selected previously
        ? document.getSelection().getRangeAt(0) // Store selection if found
        : false; // Mark as false to know no selection existed before
    el.select(); // Select the <textarea> content
    document.execCommand("copy"); // Copy - only works as a result of a user action (e.g. click events)
    document.body.removeChild(el); // Remove the <textarea> element
    if (selected) {
      // If a selection existed before copying
      document.getSelection().removeAllRanges(); // Unselect everything on the HTML document
      document.getSelection().addRange(selected); // Restore the original selection
    }
  },

  /*
   *  toast
   */

  toast: new Vue({
    el: "#wingtoast",
    methods: {
      format_options(options) {
        if (typeof options != "object") {
          options = {};
        }
        return options;
      },
      build_dom(message) {
        const self = this;
        const h = this.$createElement;
        if (Array.isArray(message[2])) {
          for (const i in message[2]) {
            message[2][i] = Array.isArray(message[2][i])
              ? self.build_dom(message[2][i])
              : message[2][i];
          }
        }
        return h(message[0], message[1], message[2]);
      },
      format_message(message) {
        if (Array.isArray(message)) {
          // an array of objects to make into a tree
          return this.build_dom(message);
        } else if (typeof message == "string" && message.charAt(0) == "[") {
          // looks like json
          return this.build_dom(JSON.parse(message));
        } else {
          // just a string
          return message;
        }
      },
      success(message, options) {
        options = this.format_options(options);
        this.$bvToast.toast(this.format_message(message), {
          autoHideDelay: options.ttl || 8000,
          variant: "success",
          toaster: "b-toaster-bottom-left",
          title: options.title || "Success",
          href: options.href,
        });
      },
      error(message, options) {
        options = this.format_options(options);
        this.$bvToast.toast(this.format_message(message), {
          autoHideDelay: options.ttl || 15000,
          variant: "danger",
          toaster: "b-toaster-top-center",
          title: options.title || "Error",
        });
      },
      warn(message, options) {
        options = this.format_options(options);
        this.$bvToast.toast(this.format_message(message), {
          autoHideDelay: options.ttl || 8000,
          variant: "warning",
          toaster: "b-toaster-bottom-left",
          title: options.title || "Warning",
        });
      },
      info(message, options) {
        options = this.format_options(options);
        this.$bvToast.toast(this.format_message(message), {
          autoHideDelay: options.ttl || 8000,
          variant: "info",
          toaster: "b-toaster-bottom-left",
          title: options.title || "Info",
        });
      },
    },
  }),

  /*
   * display an error message
   */

  error: (message, options) => {
    wing.toast.error(message);
  },

  /*
   * display a success message
   */

  success: (message, options) => {
    wing.toast.success(message, options);
  },

  /*
   * display a warning
   */

  warn: (message, options) => {
    wing.toast.warn(message);
  },

  /*
   * display some info
   */

  info: (message, options) => {
    wing.toast.info(message);
  },

  /*
   * generate a random string
   */

  string_random: (length) => {
    var text = "";
    if (!length) {
      length = 6;
    }
    var possible =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    for (var i = 0; i < length; i++)
      text += possible.charAt(Math.floor(Math.random() * possible.length));
    return text;
  },

  /*
   * parses a date into a moment object
   */

  parse_date: (input, timezone) => {
    if (typeof moment === "undefined") {
      wing.error("moment.js not installed");
      return input;
    } else {
      if (Array.isArray(input) && typeof input[0] === "string") {
        // date + input pattern
        date = moment(input[0], input[1], true);
      } else if (typeof input === "string" && input.length == 19) {
        // mysql datetime
        var parts = input.split(/\s/);
        var string = parts[0] + "T" + parts[1] + "+00:00"; // wing dates are UTC
        date = moment.utc(string);
      } else if (typeof input === "string" && input.length == 10) {
        // mysql date
        date = moment.utc(input, "YYYY-MM-DD", true);
      } else if (input instanceof moment) {
        date = input;
      } else if (typeof input === "number" && input > 1000000000000) {
        // milliseconds since epoch
        date = moment(input);
      } else if (typeof input === "number") {
        // seconds since epoch
        date = moment.unix(input);
      } else {
        // must be a normal date
        date = moment(input);
      }
      if (typeof moment.tz === "function" && typeof timezone !== "undefined") {
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
    if (!results[2]) return "";
    return decodeURIComponent(results[2].replace(/\+/g, " "));
  },

  firebase(user_id) {
    if (typeof firebase === "undefined") {
      wing.error("Firebase client not installed");
      return null;
    } else {
      const promise = axios
        .get("/api/user/" + user_id + "/firebase-jwt")
        .then(function (response) {
          const config = response.data.result;
          firebase.initializeApp({
            databaseURL: "https://" + config.database + ".firebaseio.com",
            apiKey: config.api_key,
            authDomain: config.id + ".firebaseapp.com",
          });
          firebase
            .auth()
            .signInWithCustomToken(config.jwt)
            .catch(function (error) {
              console.log("Firebase login failed!", error);
            });
          firebase
            .database()
            .ref("/status/" + user_id)
            .on("child_added", function (snapshot) {
              const message = snapshot.val();
              if (
                _.includes(["warn", "info", "error", "success"], message.type)
              ) {
                wing[message.type](message.message);
                setTimeout(function () {
                  snapshot.ref.remove();
                }, 1000);
              } else {
                console.dir(message);
              }
            });
        });
    }
  },
};

/*
 * Format a date
 */

Vue.filter("moment", function (input, format, timezone) {
  if (typeof moment !== "undefined") {
    if (!_.isString(format)) {
      format = "MMMM D, YYYY";
    }
    return wing.parse_date(input, timezone).format(format);
  }
  return input;
});

/*
 * Format a date into a relative time
 */

Vue.filter("timeago", function (input) {
  if (typeof moment !== "undefined") {
    return wing.parse_date(input).fromNow();
  }
  return input;
});

/*
 * Round a decimal to some level of precision
 */

Vue.filter("round", function (number, precision) {
  number = parseFloat(number);
  precision |= 0;
  var shift = function (number, precision, reverseShift) {
    if (reverseShift) {
      precision = -precision;
    }
    numArray = ("" + number).split("e");
    return +(
      numArray[0] +
      "e" +
      (numArray[1] ? +numArray[1] + precision : precision)
    );
  };
  return shift(Math.round(shift(number, precision, false)), precision, true);
});

/*
 * format a file size using common bytes multiples
 */

Vue.filter("bytes", function (bytes) {
  if (isNaN(parseFloat(bytes)) || !isFinite(bytes)) return "-";
  if (typeof precision === "undefined") precision = 1;
  var units = ["bytes", "kB", "MB", "GB", "TB", "PB"],
    number = Math.floor(Math.log(bytes) / Math.log(1024));
  return (
    (bytes / Math.pow(1024, Math.floor(number))).toFixed(precision) +
    " " +
    units[number]
  );
});

/*
 * Automatically save an input field.
 */

Vue.directive("autosave", {
  inserted: function (el, binding, vnode) {
    const index = _.findIndex(vnode.data.directives, { rawName: "v-model" });
    const field_index = _.findIndex(vnode.data.directives, {
      rawName: "v-autosavefield",
    });
    if (index == -1 && field_index == -1) {
      console.log(
        "Cannot use v-autosave unless on an element with a v-model or v-autosavefield."
      );
    } else {
      var delay = el.tagName == "SELECT" ? 0 : 2000;
      const delay_index = _.findIndex(vnode.data.directives, {
        rawName: "v-autosavedelay",
      });
      if (delay_index != -1) {
        delay = vnode.data.directives[delay_index].expression;
      }
      var field = null;
      if (field_index != -1) {
        field = vnode.data.directives[field_index].value;
      } else {
        var field_array = vnode.data.directives[index].expression.split(/\./);
        field = field_array[field_array.length - 1];
      }
      if (field == null) {
        console.log("v-autosave could not find v-model or v-autosavefield.");
      }
      var timer;
      var original_value = binding.value.properties[field];
      const debounce = function (e) {
        if (timer) {
          clearTimeout(timer);
        }
        if (e.keyCode == 13 && el.tagName != "TEXTAREA") {
          binding.value.save(field);
        } else {
          timer = setTimeout(function () {
            if (original_value != binding.value.properties[field]) {
              original_value = binding.value.properties[field];
              binding.value.save(field);
            }
          }, delay);
        }
      };
      el.addEventListener("keyup", debounce, false);
      el.addEventListener("change", debounce, false);
      el.addEventListener("focus", debounce, false);
      el.addEventListener(
        "blur",
        function () {
          if (original_value != binding.value.properties[field]) {
            clearTimeout(timer);
            original_value = binding.value.properties[field];
            binding.value.save(field);
          }
        },
        false
      );
    }
  },
});

/*
 * A component to get the label for a wing field with options from a single object
 */

Vue.component("wing-object-option-label", {
  template: `{{_option(object.property[property])}}`,
  props: ["object", "property"],
  methods: {
    _option(option) {
      return this.object.properties._options["_" + this.property][option];
    },
  },
});

/*
 * A component to get the label for a wing field with options from a single object
 */

Vue.component("wing-option-label", {
  template: `<template>
      <span v-if="has_list">
        {{list.field_options[_property] && list.field_options[_property][object.properties[property]]}}
      </span>
      <span v-else>
        {{object.properties._options && object.properties._options[_property][object.properties[property]]}}
      </span>
    </template>`,
  props: ["list", "object", "property"],
  computed: {
    _property() {
      return "_" + this.property;
    },
    has_list() {
      return typeof this.list !== "undefined";
    },
  },
});

/*
 * A component to generate select lists from wing options.
 */

Vue.component("wing-select", {
  template: `<select @change="object.save(property)" class="form-control custom-select" v-model="object.properties[property]">
    <option v-for="option in options()" :value="option">{{_option(option)}}</option>
  </select>`,
  props: ["object", "property"],
  methods: {
    options() {
      if ("_options" in this.object.properties) {
        return this.object.properties._options[this.property];
      }
      return [];
    },
    _option(option) {
      return this.object.properties._options["_" + this.property][option];
    },
  },
});

/*
 * A component to generate select lists from wing options.
 */

Vue.component("wing-select-new", {
  template: `<select class="form-control custom-select" v-model="list.new[property]">
    <option v-for="option in options()" :value="option">{{_option(option)}}</option>
  </select>`,
  props: ["list", "property"],
  methods: {
    options() {
      if (this.property in this.list.field_options) {
        return this.list.field_options[this.property];
      }
      return [];
    },
    _option(option) {
      return this.list.field_options["_" + this.property][option];
    },
  },
});

/*
 * Standardize pagination formatting.
 */

Vue.component("wing-pagination", {
  template: `<template><b-row v-if="list.paging.total_pages > 1">
            <b-col>
                <b-pagination size="md" @change="change_page()" :total-rows="list.paging.total_items" v-model="list.paging.page_number" limit="10" last-number first-number :per-page="list.paging.items_per_page"></b-pagination>
            </b-col>
            <b-col lg="2" md="3" sm="4">
                <b-form-select id="items_per_page" @change="list.search_fast()" v-model="list.paging.items_per_page" :options="list.items_per_page_options" class="mb-3" />
            </b-col>
        </b-row></template>`,
  props: {
    list: { required: 1 },
    scroll_to_id: { default: null },
  },
  methods: {
    change_page() {
      var self = this;
      self.list.search_fast({
        on_success(properties) {
          if (self.scroll_to_id != null) {
            wing.scroll_to(document.getElementById(self.scroll_to_id));
          }
        },
      });
    },
  },
});

/*
 * A component to count the characters remaining in a text area.
 */

Vue.component("characters-remaining", {
  template: `<small v-bind:class="{'text-danger': toobig, 'text-warning': nearlyfull}" class="text-sm float-right form-text">Characters Remaining: {{remaining}} / {{max}}</small>`,
  props: ["property", "max"],
  computed: {
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
    },
  },
});

/*
 * A button to toggle confirmations.
 */

Vue.component("confirmation-toggle", {
  template: `<button v-if="wing.confirmations.enabled()" class="btn btn-danger" @click="wing.confirmations.toggle()"><i class="fas fa-minus-circle"></i> Disable Confirmations</button>
                <button v-else class="btn btn-secondary" @click="wing.confirmations.toggle()"><i class="fas fa-check-circle"></i> Enable Confirmations</button>`,
});

/*
 * Comments.
 */

Vue.component("comments", {
  template: `<template>
    <div class="table-responsive">
                        <table class="table table-striped">
                            <tr v-for="comment in comments.objects">
                                <td>
                                    <textarea class="form-control" v-if="comment.stash('edit')" rows="5" v-model="comment.properties.comment" v-autosave="comment" title="Comment"></textarea>
                                    <div v-if="!comment.stash('edit')" style="white-space: pre-wrap;">{{comment.properties.comment|truncate(comment.stash('comment_length')||200)}}</div>
                                    <button class="btn btn-secondary btn-sm mt-3" v-if="comment.stash('comment_length') < 1000000 && comment.properties.comment.length > 200" @click="comment.stash('comment_length',1000000)">Read More</button>
                                </td>
                                <td style="width: 40%">
                                    <a :href="comment.properties.user.profile_uri"><img v-if="comment.properties.user.avatar_uri" :src="comment.properties.user.avatar_uri" class="rounded" alt="avatar" style="height: 30px"> {{comment.properties.user.display_name}}</a>
                                    <span class="badge badge-secondary" v-if="special_badge_user_id == comment.properties.user_id">{{special_badge_label}}</span>
                                    <br>
                                    {{comment.properties.date_created|timeago}}
                                    <br>
                                    <i class="far fa-heart" v-show="!comment.properties.i_like" @click="like_comment(comment)"></i>
                                    <i class="fas fa-heart" v-show="comment.properties.i_like" @click="unlike_comment(comment)"></i>
                                    ({{comment.properties.like_count}} likes)
                                    <br>
                                    <button class="btn btn-primary btn-sm" @click="comment.stash('edit', !comment.stash('edit'))" v-if="!comment.stash('edit')" v-show="comment.properties.user_id == current_user_id || is_admin == 1"><i class="fas fa-edit"></i> Edit</button>
                                    <button class="btn btn-success btn-sm" @click="comment.stash('edit', !comment.stash('edit'))" v-if="comment.stash('edit')" v-show="comment.properties.user_id == current_user_id || is_admin == 1"><i class="fas fa-edit"></i> Save</button>
                                    <button class="btn btn-danger btn-sm" @click="comment.delete()" v-show="comment.properties.user_id == current_user_id || is_admin == 1"><i class="fas fa-trash-alt"></i> Delete</button>
                                </td>
                            </tr>
                            <tr>
                                <td>
                                    <textarea class="form-control" rows="5" v-model="comments.new.comment" title="New Comment"></textarea>
                                </td>
                                <td>
                                    <button class="btn btn-success" @click="comments.create()"><i class="fas fa-edit"></i> Add Comment</button>
                                </td>
                            </tr>
                        </table>
                    </div>
    </template>`,
  props: [
    "comments",
    "special_badge_label",
    "special_badge_user_id",
    "current_user_id",
    "is_admin",
  ],
  data() {
    return {};
  },
  methods: {
    like_comment(comment) {
      comment.call(
        "POST",
        comment.properties._relationships.self + "/like",
        {}
      );
    },
    unlike_comment(comment) {
      comment.call(
        "DELETE",
        comment.properties._relationships.self + "/like",
        {}
      );
    },
  },
});

/*
 * A toggle switch
 */

Vue.component("toggle", {
  template: `<span><span ref="toggle" :id="id" class="far toggle" v-bind:class="{'fa-toggle-on': output, 'fa-toggle-off': !output, 'text-primary': output, 'text-muted': !output}" @click="handle()" style="font-size: 170%"></span> <label @click="handle()" style="vertical-align: middle" :for="id"><slot></slot></label></span>`,
  props: {
    value: { required: 1 },
    id: {
      default: function () {
        return wing.generate_id();
      },
    },
  },
  data() {
    return {
      output: this.value,
    };
  },
  methods: {
    handle(e) {
      if (typeof this.output === "boolean") {
        this.output = !this.output;
      } else {
        this.output = this.output ? 0 : 1;
      }
      this.$emit("input", this.output);
      this.$emit("change", this.output);
    },
  },
});

/*
 * date time form control
 */

Vue.component("date-time", {
  template: `<span :id="id">
                  <b-input-group append="UTC">
                  <b-form-datepicker v-model="date" @input="handle"></b-form-datepicker>
                  <b-form-timepicker v-model="time" @input="handle" locale="en"></b-form-timepicker>
                  </b-input-group>
              </span>`,
  props: {
    value: { required: 1 },
    id: {
      default: function () {
        return wing.generate_id();
      },
    },
  },
  data() {
    var date = moment(this.value);
    return {
      date: date.format("YYYY-MM-DD"),
      time: date.format("HH:mm:ss"),
    };
  },
  methods: {
    handle(e) {
      var output = this.date + " " + this.time;
      this.$emit("input", output);
      this.$emit("change", output);
    },
  },
});

/*
 * markdown editor - https://github.com/code-farmer-i/vue-markdown-editor
 */

Vue.component("markdown-editor", {
  template: `<div class="row">
          <div class="col-lg mb-3">
              <v-md-editor v-model="object.properties[property]" :toolbar="toolbar" :ref="id" :id="id" @change="fix_first()" @save="save()" :left-toolbar="left_toolbar" :right-toolbar="right_toolbar" mode="edit" height="90vh"></v-md-editor>
              <slot name="default"></slot>
          </div>
          <div class="col-lg mb-3" v-if="rendered">
              <div v-html="object.properties[rendered]"></div>
          </div>
      </div>`,
  props: {
    object: { required: 1 },
    property: { required: 1 },
    rendered: {},
    help: {
      default: "http://help.thegamecrafter.com/article/253-advanced-formatting",
    },
    id: {
      default: function () {
        return wing.generate_id();
      },
    },
  },
  data() {
    var self = this;
    return {
      first: true,
      left_toolbar:
        "save | undo redo | h bold italic strikethrough quote | ul ol table hr | link | help fullscreen",
      right_toolbar: "",
      toolbar: {
        help: {
          title: "Formatting Help",
          icon: "fas fa-question-circle",
          action(editor) {
            window.open(self.help);
          },
        },
      },
    };
  },
  methods: {
    save() {
      var self = this;
      var cursor = self.$refs[self.id].codemirrorInstance.getCursor();
      self.$refs[self.id].codemirrorInstance.setOption("readOnly", "nocursor");
      var params = {};
      params[self.property] = self.object.properties[self.property];
      self.object._partial_update(params, {
        on_success() {
          setTimeout(function () {
            // reset the cursor where it was
            self.$refs[self.id].codemirrorInstance.scrollIntoView({
              line: cursor.line + 5,
            });
            self.$refs[self.id].codemirrorInstance.setOption("readOnly", false);
            self.$refs[self.id].codemirrorInstance.setCursor(cursor);
            self.$refs[self.id].codemirrorInstance.focus();
          }, 0);
        },
      });
    },
    fix_first() {
      // the editor calls a change event immediately upon load for some reason
      if (this.first) {
        this.first = false;
      } else {
        this.debounced_save();
      }
    },
    debounced_save: _.debounce(function () {
      this.save();
    }, 3500),
  },
});

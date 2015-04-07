/*
 * AngularJS module for Wing
 */

angular.module('wing',[])

/*
 * Handle wing authentication and exceptions
 */

.config( function($httpProvider) {
    $httpProvider.defaults.withCredentials = true;
    $httpProvider.interceptors.push(wing.angular_http_interceptor);
})

/*
 * Filter for wing datetime objects
 */

.filter('datetime', ['$filter', wing.angular_datetime_filter])

/*
 * Confirmations manager
 */

.factory('confirmations', [function () {
    var enabled = true;
    return {
        enabled : function() {
            return enabled;
        },
        
        disabled : function() {
            return !enabled;
        },
        
        toggle : function() {
            if (enabled == true) {
                if (confirm('Are you sure you want to disable confirmations on things like deleting files?')) {
                    enabled = false;
                }
            }
            else {
                enabled = true;
            }
        },
        
    };
}])

/*
 * Generic wing object list manipulation for Wing using Angular.
 */

.factory('objectListManager', ['$http','objectManager',function ($http, objectManager) {
    return function(behavior) {
        this.objects = [];
        this.paging = [];
        
        this.find_object = function(id) {
            var self = this;
            for (var i = 0, len = self.objects.length; i < len; i++) {
                if (self.objects[i].properties.id === id) return i;
            }
            return -1;
        }
        
        this._create_object_manager = function(properties) {
            var self = this;
            return new objectManager({
                properties : properties,
                fetch_options : behavior.fetch_options,
                create_api : behavior.create_api,
                on_create : behavior.on_create,
                on_update : behavior.on_update,
                on_delete : function(properties) {
                    var myself = this;
                    if ('on_delete' in behavior) {
                        behavior.on_delete(properties);
                    }
                    var index = self.find_object(properties.id);
                    if (index >= 0) {
                        self.objects.splice(index, 1);
                    }
                },
            });
        };
        
        this.search = function(options) {
            var self = this;
            pagination = {
                _page_number : self.paging.page_number || 1,
                _items_per_page : self.paging.items_per_page || 10,
            };
            var params = wing.merge(behavior.fetch_options, pagination);
            if (typeof options !== 'undefined' && typeof options.query !== 'undefined') {
                params = wing.merge(params, options.query);
            }
            $http.get(behavior.list_api, { params : params })
            .success(function (data) {
                self.objects = [];
                for (var index = 0; index < data.result.items.length; index++) {
                    self.objects.push(self._create_object_manager(data.result.items[index]));
                }
                self.paging = data.result.paging;
            });
            return self;
        };
        
        this.all = function(page_number) {
            var self = this;
            var params = wing.merge({
                _page_number: page_number || 1,
                _items_per_page: 10,
            }, behavior.fetch_options);
            $http.get(behavior.list_api, { params : params })
            .success(function (data) {
                for (var index in data.result.items) {
                    self.objects.push(self._create_object_manager(data.result.items[index]));
                }
                if (data.result.paging.page_number < data.result.paging.total_pages) {
                    self.all(data.result.paging.next_page_number);
                }
            });
            return self;
        };
        
        this.create = function(properties, options) {
            var self = this;
            var new_object = self._create_object_manager(properties);
            var add_it = function() {
                self.objects.push(new_object);
            };
            if (typeof options !== 'undefined') {
                if (typeof options.on_success !== 'undefined') {
                    var success = options.on_success;
                    options.on_success = function(properties) {
                        add_it();
                        success(properties);
                    };
                }
                else {
                    options['on_success'] = add_it;
                }
            }
            else {
                options = {on_success : add_it};
            }
            new_object.create(properties, options);
            return self;
        };
        
        this.update =  function(index, options) {
            var self = this;
            self.objects[index].update(options);
            return self;
        };

        this.save =  function(index, property) {
            var self = this;
            self.objects[index].save(property);
            return self;
        };

        this.partial_update =  function(index, properties, options) {
            var self = this;
            self.objects[index].partial_update(properties, options);
            return self;
        };

        this.delete = function(index, options) {
            var self = this;
            self.objects[index].delete(options);
            return self;
        };
    };
}])

/*
 * Generic wing object manipulation for Wing using Angular.
 */

.factory('objectManager', ['$http','confirmations',function ($http, confirmations) {
    return function(behavior) {
        this.properties = behavior.properties || {};
        
        this.fetch = function(options) {
            var self = this;
            $http.get(behavior.fetch_api, { params : behavior.fetch_options })
            .success(function (data) {
                self.properties = data.result;
                if (typeof options !== 'undefined' && typeof options.on_success !== 'undefined') {
                    options.on_success(data.result);
                }
                if (typeof behavior.on_fetch !== 'undefined') {
                    behavior.on_fetch(data.result);
                }
            });
            return self;
        };
        
        this.create = function(properties, options) {
            var self = this;
            var params = wing.merge(behavior.fetch_options, properties );
            $http.post(behavior.create_api, params)
            .success(function (data) {
                self.properties = data.result;
                if (typeof options !== 'undefined' && typeof options.on_success !== 'undefined') {
                    options.on_success(data.result);
                }
                if (typeof behavior.on_create !== 'undefined') {
                    behavior.on_create(data.result);
                }
            });
            return self;
        };
        
        this.update =  function(options) {
            var self = this;
            self.partial_update(self.properties, options);
            return self;
        };
        
        this.save = function(property) {
            var self = this;
            var update = {};
            update[property] = self.properties[property];
            self.partial_update(update);
            return self;
        };

        this.partial_update =  function(properties, options) {
            var self = this;
            var params = wing.merge(behavior.fetch_options, properties);
            $http.put(self.properties._relationships.self, params)
            .success(function (data) {
                self.properties = data.result;
                if (typeof options !== 'undefined' && typeof options.on_success !== 'undefined') {
                    options.on_success(data.result);
                }
                if (typeof behavior.on_update !== 'undefined') {
                    behavior.on_update(data.result);
                }
            });
            return self;
        };
        
        this.delete = function(options) {
            var self = this;
            var object = self.properties;
            var message = 'Are you sure?';
            if ('name' in object) {
                message = 'Are you sure you want to delete ' + object.name + '?';
            }
            if (confirmations.disabled() || confirm(message)) {
                $http.delete(object._relationships.self, {})
                .success(function (data) {
                    if (typeof options !== 'undefined' && typeof options.on_success !== 'undefined') {
                        options.on_success(object);
                    }
                    if (typeof behavior.on_delete !== 'undefined') {
                        behavior.on_delete(object);
                    }
                    self.properties = {};
                });
            }
            return self;
        };
    };
}])

/*
 * If you specify an input[number] tag then this automatically ensures that it's formatted as a number so that angular doesn't get pissed off
 */

.directive('input', [function() {
    return {
        restrict: 'E',
        require: '?ngModel',
        link: function(scope, element, attrs, ngModel) {
            if (
                   'undefined' !== typeof attrs.type
                && 'number' === attrs.type
                && ngModel
            ) {
                ngModel.$formatters.push(function(modelValue) {
                    return Number(modelValue);
                });

                ngModel.$parsers.push(function(viewValue) {
                    return Number(viewValue);
                });
            }
        }
    }
}])

/*
 * Gives you a nice wrapper so you can automatically save a field like wing.attach_autosave(). You can do:
 *
 * <input ng-model="object.properties.property_name" autosave="object">
 *
 * which is the equivalent of
 *
 * <input ng-model="object.properties.property_name" options="{ updateOn: 'blur' }" ng-change="object.save('property_name')">
 * 
 */

.directive('autosave', [function() {
    return {
        restrict: 'A',
        scope : {
            autosave : '=',
        },
        link: function(scope, element, attrs) {
            element.bind('change', function(){
                var property_name = attrs.ngModel.match(/(?=[^.]*$)(\w+)/)[1];
                scope.autosave.save(property_name);
            });
        }
    }
}])

/*
 * Give syou a nice way to generate select lists from wing options
 *
 * <wing-select object="object_name" property="property_name"></wing-select>
 *
 * which is the equivalent of
 *
 * <select ng-options="option.toString() as object.properties._options._property_name[option] for option in object.properties._options.property_name" autosave="object" class="form-control" ng-model="object.properties.property_name"></select>
 * 
 */

.directive('wingSelect', ['$compile', function($compile) {
    return {
        restrict: 'E',
        scope : {
            object : '=',
        },
        link: function(scope, element, attrs) {
            var object_name = attrs.object;
            var property_name = attrs.property;
            var options_property_name = '_' + property_name;
            var html = '<select force-string ng-options="option.toString() as object.properties._options.' + options_property_name + '[option] for option in object.properties._options.' + property_name + '" autosave="object" class="form-control" ng-model="object.properties.' + property_name + '"></select>';
            var e = $compile(html)(scope);
            element.replaceWith(e);
        }
    }
}])

/*
 * Forces the model to be a string even if it's labeled a number.
 */

.directive('forceString', ['$compile', function($compile) {
    return {
        restrict: 'A',
        require: 'ngModel',
        link: function(scope, element, attrs, ngModel) {
            ngModel.$formatters.push(function(modelValue) {
                return modelValue.toString();
            });
        }
    }
}])
;

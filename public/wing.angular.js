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

.factory('objectListManager', ['$http','confirmations',function ($http, confirmations) {
    return function(behavior) {
        this.objects = [];
        this.paging = [];
        
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
                self.objects = data.result.items;
                self.paging = data.result.paging;
            });
        };
        
        this.all = function(page_number) {
            var self = this;
            var params = wing.merge({
                _page_number: page_number || 1,
                _items_per_page: 10,
            }, behavior.fetch_options);
            $http.get(behavior.list_api, { params : params })
            .success(function (data) {
                self.objects = self.objects.concat(data.result.items);
                if (data.result.paging.page_number < data.result.paging.total_pages) {
                    self.all(data.result.paging.next_page_number);
                }
            });
        };
        
        this.create = function(properties, options) {
            var self = this;
            var params = wing.merge(behavior.fetch_options, properties );
            $http.post(behavior.create_api, params)
            .success(function (data) {
                self.objects.push(data.result);
                if (typeof options !== 'undefined' && typeof options.on_success !== 'undefined') {
                    options.on_success(data.result, self.objects.length - 1);
                }
                if (typeof behavior.on_create !== 'undefined') {
                    behavior.on_create(data.result, self.objects.length - 1);
                }
            });
        };
        
        this.update =  function(index, options) {
            var self = this;
            self.partial_update(index, self.objects[index], options);
        };

        this.partial_update =  function(index, properties, options) {
            var self = this;
            var params = wing.merge(behavior.fetch_options, properties);
            $http.put(self.objects[index]._relationships.self, params)
            .success(function (data) {
                self.objects[index] = data.result;
                if (typeof options !== 'undefined' && typeof options.on_success !== 'undefined') {
                    options.on_success(data.result, index);
                }
                if (typeof behavior.on_update !== 'undefined') {
                    behavior.on_update(data.result, index);
                }
            });
        };

        this.delete = function(index, options) {
            var self = this;
            var object = self.objects[index];
            var message = 'Are you sure?';
            if ('name' in object) {
                message = 'Are you sure you want to delete ' + object.name + '?';
            }
            if (confirmations.disabled() || confirm(message)) {
                $http.delete(object._relationships.self, {})
                .success(function (data) {
                    self.objects.splice(index, 1);
                    if (typeof options !== 'undefined' && typeof options.on_success !== 'undefined') {
                        options.on_success(object, index);
                    }
                    if (typeof behavior.on_delete !== 'undefined') {
                        behavior.on_delete(object, index);
                    }
                });
            }
        };
    };
}])

/*
 * Generic wing object manipulation for Wing using Angular.
 */

.factory('objectManager', ['$http','confirmations',function ($http, confirmations) {
    return function(behavior) {
        this.properties = [];
        
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
        };
        
        this.update =  function(options) {
            var self = this;
            self.partial_update(self.properties, options);
        };
        
        this.save = function(property) {
            var self = this;
            var update = {};
            update[property] = self.properties[property];
            self.partial_update(update);
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
                    self.properties = {};
                    if (typeof options !== 'undefined' && typeof options.on_success !== 'undefined') {
                        options.on_success(object);
                    }
                    if (typeof behavior.on_delete !== 'undefined') {
                        behavior.on_delete(object);
                    }
                });
            }
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
}]);

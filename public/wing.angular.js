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

    //initialize get if not there
    if (!$httpProvider.defaults.headers.get) {
        $httpProvider.defaults.headers.get = {};    
    }    

    // Answer edited to include suggestions from comments
    // because previous version of code introduced browser-related errors

    //disable IE ajax request caching
    $httpProvider.defaults.headers.get['If-Modified-Since'] = 'Mon, 26 Jul 1997 05:00:00 GMT';
    // extra
    $httpProvider.defaults.headers.get['Cache-Control'] = 'no-cache';
    $httpProvider.defaults.headers.get['Pragma'] = 'no-cache';
})

/*
 * Filter for wing datetime objects
 */

.filter('datetime', ['$filter', wing.angular_datetime_filter])

/*
 * Converts a wing datetime field into a human readable string
 *
 * Borrowed from: https://github.com/uttesh/ngtimeago
 */
.filter('timeago', function() {
    return function(input, p_allowFuture) {
    
        var substitute = function (stringOrFunction, number, strings) {
                var string = angular.isFunction(stringOrFunction) ? stringOrFunction(number, dateDifference) : stringOrFunction;
                var value = (strings.numbers && strings.numbers[number]) || number;
                return string.replace(/%d/i, value);
            },
            nowTime = (new Date()).getTime(),
            datetime = input.replace(/\s/,'T') + 'Z';
            date = (new Date(datetime)).getTime();
            //refreshMillis= 6e4, //A minute
            allowFuture = p_allowFuture || false,
            strings= {
                prefixAgo: '',
                prefixFromNow: '',
                suffixAgo: "ago",
                suffixFromNow: "from now",
                seconds: "less than a minute",
                minute: "about a minute",
                minutes: "%d minutes",
                hour: "about an hour",
                hours: "about %d hours",
                day: "a day",
                days: "%d days",
                month: "about a month",
                months: "%d months",
                year: "about a year",
                years: "%d years"
            },
            dateDifference = nowTime - date,
            words = 0,
            seconds = Math.abs(dateDifference) / 1000,
            minutes = seconds / 60,
            hours = minutes / 60,
            days = hours / 24,
            years = days / 365,
            separator = strings.wordSeparator === undefined ?  " " : strings.wordSeparator,
        
           
            prefix = strings.prefixAgo,
            suffix = strings.suffixAgo;
            
        if (allowFuture) {
            if (dateDifference < 0) {
                prefix = strings.prefixFromNow;
                suffix = strings.suffixFromNow;
            }
        }

        words = seconds < 45 && substitute(strings.seconds, Math.round(seconds), strings) ||
        seconds < 90 && substitute(strings.minute, 1, strings) ||
        minutes < 45 && substitute(strings.minutes, Math.round(minutes), strings) ||
        minutes < 90 && substitute(strings.hour, 1, strings) ||
        hours < 24 && substitute(strings.hours, Math.round(hours), strings) ||
        hours < 42 && substitute(strings.day, 1, strings) ||
        days < 30 && substitute(strings.days, Math.round(days), strings) ||
        days < 45 && substitute(strings.month, 1, strings) ||
        days < 365 && substitute(strings.months, Math.round(days / 30), strings) ||
        years < 1.5 && substitute(strings.year, 1, strings) ||
        substitute(strings.years, Math.round(years), strings);
        prefix.replace(/ /g, '')
        words.replace(/ /g, '')
        suffix.replace(/ /g, '')
        return (prefix+' '+words+' '+suffix+' '+separator);
        
    };
})

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
        this.creation_options = {};
        
        this.fetch_creation_options = function() {
            var self = this;
            var uri = behavior.create_api + '/_options';
            $http.get(uri, {})
            .success(function(data) {
                self.creation_options = data.result;
            });
        };
        
        this.find_object = function(id) {
            var self = this;
            for (var i = 0, len = self.objects.length; i < len; i++) {
                if (self.objects[i].properties.id === id) return i;
            }
            return -1;
        };
        
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
            var params = wing.merge(pagination, behavior.fetch_options);
            if (typeof options !== 'undefined' && typeof options.query !== 'undefined') {
                params = wing.merge(params, options.query);
            }
            return $http.get(behavior.list_api, { params : params })
            .then(function (response) {
                var data = response.data;
                self.objects = [];
                for (var index = 0; index < data.result.items.length; index++) {
                    self.objects.push(self._create_object_manager(data.result.items[index]));
                    if (typeof options !== 'undefined' && typeof options.on_each !== 'undefined') {
                        options.on_each(data.result.items[index]);
                    }
                    if (typeof behavior.on_each !== 'undefined') {
                        behavior.on_each(data.result.items[index]);
                    }
                }
                self.paging = data.result.paging;
                var items = data.result.items;
                if (typeof options !== 'undefined' && typeof options.prepend_item !== 'undefined') { // useful for typeahead
                    items.unshift(options.prepend_item);
                }
                if (typeof options !== 'undefined' && typeof options.on_success !== 'undefined') {
                    options.on_success();
                }
                if (typeof behavior.on_success !== 'undefined') {
                    behavior.on_success();
                }
                return items;
            });
            return self;
        };
        
        this.all = function(options, page_number) {
            var self = this;
            var params = wing.merge({
                _page_number: page_number || 1,
                _items_per_page: 10,
            }, behavior.fetch_options);
            $http.get(behavior.list_api, { params : params })
            .success(function (data) {
                for (var index in data.result.items) {
                    self.objects.push(self._create_object_manager(data.result.items[index]));
                    if (typeof options !== 'undefined' && typeof options.on_each !== 'undefined') {
                        options.on_each(data.result.items[index]);
                    }
                    if (typeof behavior.on_each !== 'undefined') {
                        behavior.on_each(data.result.items[index]);
                    }
                }
                if (data.result.paging.page_number < data.result.paging.total_pages) {
                    self.all(options, data.result.paging.next_page_number);
                }
                if (typeof options !== 'undefined' && typeof options.on_success !== 'undefined') {
                    options.on_success();
                }
                if (typeof behavior.on_success !== 'undefined') {
                    behavior.on_success();
                }
            });
            return self;
        };

	this.options_api = function() {
	    if (behavior.options_api != null) {
                return behavior.options_api;
            }
            return behavior.create_api + '/_options';
        };
        
        this.fetch_options = function(store_data_here, options) {
            var self = this;
            $http.get(self.options_api(), {})
            .success(function (data) {
		for(var key in data.result) {
    		    store_data_here[key] = data.result[key];
		}
                if (typeof options !== 'undefined' && typeof options.on_success !== 'undefined') {
                    options.on_success(data.result);
                }
            })
            .error(function (data) {
                if (typeof options !== 'undefined' && typeof options.on_error !== 'undefined') {
                    options.on_error(data.result);
                }
            });
            return self;
        };

        this.create = function(properties, options) {
            var self = this;
            var new_object = self._create_object_manager(properties);
            var add_it = function() {
                if (typeof options !== 'undefined' && typeof options.unshift !== 'undefined' && options.unshift == true) {
                    self.objects.unshift(new_object);
                }
                else {
                    self.objects.push(new_object);
                }
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
            $http.get((typeof self.properties !== 'undefined' && typeof self.properties._relationships !== 'undefined' && self.properties._relationships.self) || behavior.fetch_api, { params : behavior.fetch_options })
            .success(function (data) {
                self.properties = data.result;
                if (typeof options !== 'undefined' && typeof options.on_success !== 'undefined') {
                    options.on_success(data.result);
                }
                if (typeof behavior.on_fetch !== 'undefined') {
                    behavior.on_fetch(data.result);
                }
            })
            .error(function (data) {
                if (typeof options !== 'undefined' && typeof options.on_error !== 'undefined') {
                    options.on_error(data.result);
                }
                if (typeof behavior.on_error !== 'undefined') {
                    behavior.on_error(data.result);
                }
            });
            return self;
        };
        
        this.create = function(properties, options) {
            var self = this;
            var params = wing.merge(behavior.fetch_options, properties);
            $http.post(behavior.create_api, params)
            .success(function (data) {
                self.properties = data.result;
                if (typeof options !== 'undefined' && typeof options.on_success !== 'undefined') {
                    options.on_success(data.result);
                }
                if (typeof behavior.on_create !== 'undefined') {
                    behavior.on_create(data.result);
                }
            })
            .error(function (data) {
                if (typeof options !== 'undefined' && typeof options.on_error !== 'undefined') {
                    options.on_error(data.result);
                }
                if (typeof behavior.on_error !== 'undefined') {
                    behavior.on_error(data.result);
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

        this.call =  function(method, uri, properties, options) {
            var self = this;
            var params = wing.merge(behavior.fetch_options, properties);
            var q;
            if (method.toLowerCase() == 'get') {
                q = $http.get(uri, { params : params });
            }
            else if (method.toLowerCase() == 'delete') {
                q = $http.delete(uri, { params : params });
            }
            else if (method.toLowerCase() == 'post') {
                q = $http.post(uri, params);
            }
            else if (method.toLowerCase() == 'put') {
                q = $http.put(uri, params);
            }
            q.success(function (data) {
                self.properties = data.result;
                if (typeof options !== 'undefined' && typeof options.on_success !== 'undefined') {
                    options.on_success(data.result);
                }
            })
            .error(function (data) {
                if (typeof options !== 'undefined' && typeof options.on_error !== 'undefined') {
                    options.on_error(data.result);
                }
                if (typeof behavior.on_error !== 'undefined') {
                    behavior.on_error(data.result);
                }
            });
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
            })
            .error(function (data) {
                if (typeof options !== 'undefined' && typeof options.on_error !== 'undefined') {
                    options.on_error(data.result);
                }
                if (typeof behavior.on_error !== 'undefined') {
                    behavior.on_error(data.result);
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
                })
                .error(function (data) {
                    if (typeof options !== 'undefined' && typeof options.on_error !== 'undefined') {
                        options.on_error(data.result);
                    }
                    if (typeof behavior.on_error !== 'undefined') {
                        behavior.on_error(data.result);
                    }
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
 * Force value to be a number. 
 */

.directive('forceNumber', [function() {
    return {
        restrict: 'A',
        require: '?ngModel',
        link: function(scope, element, attrs, ngModel) {
            if (
                ngModel
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
 * <input ng-model="object.properties.property_name" ng-model-options="{ updateOn: 'blur' }" ng-change="object.save('property_name')">
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
                if (typeof modelValue !== 'undefined') {
                    return modelValue.toString();
                }
            });
        }
    }
}])

;

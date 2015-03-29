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
 * Generic wing object list manipulation for Wing using Angular.
 */

.factory('objectListManager', ['$http',function ($http) {
    var confirmations_enabled = true;
    var fetch_options = {};
    var merge = function (obj1,obj2){ // Our merge function, until angular.merge() appears in 1.4
        var result = {}; // return result
        for(var i in obj1){      // for every property in obj1 
            if ((i in obj2) && (typeof obj1[i] === "object") && (i !== null)){
                result[i] = merge(obj1[i],obj2[i]); // if it's an object, merge   
            }else{
               result[i] = obj1[i]; // add it to result
            }
        }
        for(i in obj2){ // add the remaining properties from object 2
            if(i in result){ //conflict
                continue;
            }
            result[i] = obj2[i];
        }
        return result;
    };
        
    return {
        confirmations_enabled : function() { return confirmations_enabled },
        
        toggle_confirmations : function() {
            if (confirmations_enabled == true) {
                if (confirm('Are you sure you want to disable confirmations on things like deleting files?')) {
                    confirmations_enabled = false;
                }
            }
            else {
                confirmations_enabled = true;
            }
        },
        
        object_map : function(behavior) {
            this.objects = [];
            this.paging = [];
            
            this.search = function(options) {
                var self = this;
                pagination = {
                    _page_number : self.paging.page_number || 1,
                    _items_per_page : self.paging.items_per_page || 10,
                };
                var params = merge(behavior.fetch_options, pagination);
                if (typeof options !== 'undefined' && typeof options.query !== 'undefined') {
                    params = merge(params, options.query);
                }
                $http.get(behavior.list_api, { params : params })
                .success(function (data) {
                    self.objects = data.result.items;
                    self.paging = data.result.paging;
                });
            };
            
            this.all = function(page_number) {
                var self = this;
                var params = merge({
                    _page_number: page_number || 1,
                    _items_per_page: 10,
                }, behavior.fetch_options);
                $http.get(behavior.list_api, { params : params })
                .success(function (data) {
                    self.objects = self.objects.concat(data.result.items);
                    if (data.result.paging.page_number < data.result.paging.total_pages) {
                        this.all(data.result.paging.next_page_number);
                    }
                });
            };
            
            this.create = function(properties, options) {
                var self = this;
                var params = merge(behavior.fetch_options, properties );
                $http.post(behavior.create_api, params)
                .success(function (data) {
                    self.objects.push(data.result);
                    if (typeof options !== 'undefined' && typeof options.on_success !== 'undefined') {
                        on_success(data.result, self.objects.length - 1);
                    }
                    if (typeof behavior.on_create !== 'undefined') {
                        behavior.on_create(data.result, self.objects.length - 1);
                    }
                });
            };
            
            this.update =  function(index, options) {
                var self = this;
                var params = merge(behavior.fetch_options, self.objects[index]);
                $http.put(self.objects[index]._relationships.self, params)
                .success(function (data) {
                    self.objects[index] = data.result;
                    if (typeof options !== 'undefined' && typeof options.on_success !== 'undefined') {
                        on_success(data.result, index);
                    }
                    if (typeof behavior.on_update !== 'undefined') {
                        behavior.on_update(data.result, index);
                    }
                });
            };

            this.update_if_dirty =  function(index, options) {
                var self = this;
                if (self.objects[index]._is_dirty) {
                    this.update(index, options);
                }
            };
            
            this.delete = function(index, options) {
                var self = this;
                var message = 'Are you sure?';
                if ('name' in self.objects[index]) {
                    message = 'Are you sure you want to delete ' + self.objects[index].name + '?';
                }
                if (confirmations_enabled == false || confirm(message)) {
                    $http.delete(self.objects[index]._relationships.self, {})
                    .success(function (data) {
                        self.objects.splice(index, 1);
                        if (typeof options !== 'undefined' && typeof options.on_success !== 'undefined') {
                            on_success(data.result, index);
                        }
                        if (typeof behavior.on_delete !== 'undefined') {
                            behavior.on_delete(data.result, index);
                        }
                    });
                }
            };


        },
    };
}]);

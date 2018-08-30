const chat = {cache : { users : {} }, commands : [], last_message_text : '', last_message_timestamp : Date.now(), icons : {}};

chat.init = function(config) {

    chat.current_user = config.user;

    /* firebase setup */
    chat.firebase = firebase.initializeApp({
        databaseURL : 'https://'+config.firebase.database+'.firebaseio.com',
        apiKey : config.firebase.api_key,
        authDomain : config.firebase.id+'.firebaseapp.com',
    });
    chat.db = chat.firebase.database();
    chat.refs = {
        users : chat.db.ref('chat/users'),
        likes : chat.db.ref('chat/likes'),
        bans : chat.db.ref('chat/bans'),
        moderators : chat.db.ref('chat/moderators'),
        rooms : chat.db.ref('chat/rooms'),
        messages : chat.db.ref('chat/messages'),
        current_user : chat.db.ref('chat/users/'+chat.current_user.id),
        current_user_invites : chat.db.ref('chat/users/'+chat.current_user.id+'/invites'),
    };
    chat.lookup_user = function (user_id, callback) {
        var self = this;
        if (!( user_id in chat.cache.users)) {
          chat.refs.users.child(user_id).once('value', function (snap) {
            var user = snap.val();
            chat.cache.users[user_id] = user;
            callback(user);
          });
        }
        else {
            callback(chat.cache.users[user_id]);
        }
    };
    chat.refs.users.on('child_changed', function(snapshot) {
        const user = snapshot.val();
        chat.cache.users[user.id] = user;
    });
    chat.lookup_user_by_name = function (name, callback) {
        var self = this;
        let user = _.find(chat.cache.users, function(o) { return o.name == name});
        if (typeof user == 'undefined') {
            chat.refs.users.orderByChild('name').equalTo(name).limitToFirst(1).on('child_added', function(snapshot) {
                user = snapshot.val();
                chat.cache.users[user.id] = user;
                callback(user);
            });
        }
        else {
            callback(user);
        }
    };

    /* icons */
    chat.icons = {
        frown : 'fa-frown-open',
        angry : 'fa-angry',
        tired : 'fa-tired',
        wow : 'fa-surprise',
        wink : 'fa-grin-wink',
        cry : 'fa-sad-cry',
        disbelief : 'fa-meh-rolling-eyes',
        blank : 'fa-meh-blank',
        excited : 'fa-grin-stars',
        love : 'fa-grin-hearts',
        grin : 'fa-grin-squint',
        sweat : 'fa-grin-beam-sweat',
        smile : 'fa-smile',
        laugh : 'fa-laugh-beam',
        kiss : 'fa-kiss-wink-heart',
        tease : 'fa-grin-tongue-wink',
        shock : 'fa-flushed',
        dizzy : 'fa-dizzy',
        happy : 'fa-grin-tears',
        pain : 'fa-grimace',
        heart : 'fa-heart',
        bomb : 'fa-bomb',
        bolt : 'fa-bolt',
        bell : 'fa-bell',
        box : 'fa-box-open',
        coffee : 'fa-coffee',
        cocktail : 'fa-cocktail',
        dice : 'fa-dice',
        rock : 'fa-hand-rock',
        paper : 'fa-hand-paper',
        scissors : 'fa-hand-scissors',
        spock : 'fa-hand-spock',
        money : 'fa-money-bill-wave',
        poo : 'fa-poo',
        rocket : 'fa-rocket',
    };
    chat.add_icon = function(key, classname) {
        chat[key] = classname;
    };

    /* commands */

    chat.add_command = function(command) {
        chat.commands.push(command);
    };

    chat.add_command({
        match   : /^\/help$/,
        func : function(text, ui) {
            var help = '<h5>Help</h5>';
            const sorted = _.orderBy(chat.commands, ['name'],['asc']);
            for (var i in sorted) {
                if (sorted[i].moderator_only && !chat.current_user.moderator) {
                    continue; // skip it
                }
                help += '<p><b>' + sorted[i].name + '</b> - ' + sorted[i].help;
                if (sorted[i].moderator_only) {
                    console.log('got here');
                    help += ' <span class="badge badge-secondary">Moderator Only</span>';
                }
                help += '</p>';
            }
            ui.add_system_message(help);
        },
        name    : "/help",
        help    : "Display this message."
    });

    chat.add_command({
        match   : /^\/me\s+(.*)$/,
        func : function(text, ui) {
            const self = this;
            const search = text.match(self.match);
            chat.add_message(ui.room.id, search[1], { type : 'emote' });
        },
        name    : "/me [message]",
        help    : "Emote an action."
    });

    chat.add_command({
        match   : /^\/notice\s+(.*)$/,
        func : function(text, ui) {
            const self = this;
            const search = text.match(self.match);
            chat.add_message(ui.room.id, search[1], { type : 'notice' });
        },
        name    : "/notice [announcement]",
        help    : "Post an announcement for all to see. Please use sparingly and not in jest.",
        moderator_only : true,
    });

    chat.add_command({
        match   : /^\/badge\s+(.*)$/,
        func : function(text, ui) {
            const self = this;
            const search = text.match(self.match);
            let badge = search[1].substring(0,10);
            chat.refs.current_user.child('badge').set(badge);
            ui.add_system_message('Your badge has been set to "'+badge+'".');

        },
        name    : "/badge [text]",
        help    : "A max 10 character label after your name.",
        moderator_only : true,
    });

    chat.add_command({
        match   : /^\/badge-color\s+(.*)$/,
        func : function(text, ui) {
            const self = this;
            const search = text.match(self.match);
            let color = search[1];
            const colors = ['red','orange','yellow','green','blue','purple'];
            if (colors.indexOf(color) == -1) {
                color = 'grey';
            }
            chat.refs.current_user.child('badge_color').set(color);
            ui.add_system_message('Your badge color has been set to "'+color+'".');
        },
        name    : "/badge-color [color]",
        help    : "Set a color for your badge. Must be one of grey, red, orange, yellow, green, blue, or purple.",
        moderator_only : true,
    });

    chat.add_command({
        match   : /^\/topic\s+(.*)$/,
        func : function(text, ui) {
            if (ui.room.type == 'official') {
                ui.add_system_message('You cannot modify an official room.');
            }
            else {
                const self = this;
                const search = text.match(self.match);
                chat.refs.rooms.child(ui.room.id).update({
                   name : search[1]
                }, function(error) {
                   if (error) {
                       console.dir(error);
                       wing.error('You do not have permission to modify the topic for this channel.');
                   }
                   else {
                       chat.add_message(ui.room.id, 'has set the topic to "'+search[1]+'"', { type : 'notice' });
                   }
               });
            }
        },
        name    : "/topic [new topic]",
        help    : "Change the name of the room (only if you own the room)."
    });

    chat.add_command({
        match   : /^\/whoami$/,
        func : function(text, ui) {
            var text = 'You are "' + chat.current_user.name + '", ';
            if (chat.current_user.staff) {
                text += 'a member of the staff.';
            }
            else if (chat.current_user.moderator) {
                text += 'a moderator.';
            }
            else {
                text += 'a normal user.';
            }
            ui.add_system_message(text);
        },
        name    : "/whoami",
        help    : "Display your name and privilege level."
    });

    chat.add_command({
        match   : /^\/icons$/,
        func : function(text, ui) {
            var help = '<h5>Icons</h5><div class="row">';
            Object.keys(chat.icons).sort().forEach(function(key) {
                help += '<div class="col-6 col-sm-4 col-md-3 col-lg-2 m-2"><b>:' + key + ':</b>  <span class="font-size-200 fas ' + chat.icons[key] + '"></span></div>';
            });
            help += '</div>'
            ui.add_system_message(help);
        },
        name    : "/icons",
        help    : "Display the icons you can add to your messages."
    });

    chat.add_command({
        match   : /^\/invite\s+(.*)$/,
        func : function(text, ui) {
            const self = this;
            if (ui.room.type == 'official') {
                wing.info("There's no reason to invite somone to an official room.");
            }
            else {
                const search = text.match(self.match);
                chat.lookup_user_by_name(search[1], function(user) {
                    if (typeof user == 'undefined') {
                        wing.error(search[1]+ ' was not found.');
                    }
                    else {
                        chat.send_invite(user.id, ui.room.id, ui.room.name);
                        ui.add_system_message(user.name+' was invited.');
                    }
                });
            }
        },
        name    : "/invite [name]",
        help    : "Invite a user to join the room."
    });

    chat.add_command({
        match   : /^\/roll\s+(\d+)d+(\d+)$/i,
        func : function(text, ui) {
            const self = this;
            const search = text.match(self.match);
            let sum = 0;
            let rolls = [];
            const sides = _.clamp(search[2],1,20);
            const count = _.clamp(search[1],1,20);
            for (let i = 0; i < count; i++) {
                let roll = Math.floor(sides*Math.random())+1;
                rolls.push(roll);
                sum += roll;
            }
            chat.add_message(ui.room.id, 'has rolled '+count+'d'+sides+' and got '+sum+' ('+rolls.join(', ')+').', { type : 'emote' });
        },
        name    : "/roll [n]d[s]",
        help    : "Roll a die where 'n' is the number of dice and 's' is the number of sides per die."
    });

    /* management */
    chat.send_invite = function(user_id, room_id, room_name) {
        chat.refs.rooms.child(room_id).child('authorized').child(user_id).set(true);
        chat.refs.users.child(user_id).child('invites').child(room_id).update({
            from_user_id : chat.current_user.id,
            from_user_name : chat.current_user.name,
            room_id : room_id,
            room_name : room_name,
        });
    };
    chat.add_message = function(room_id, message_text, options) {
        let text = message_text.trim();
        if (typeof options != 'object') {
             options = {};
        }

        /* stop spamming new messages */
        if ((Date.now() - chat.last_message_timestamp) / 1000 < 1) {
            alert('Slow down there! You are posting too many messages too quickly.');
            if (options.ui) {
                options.ui.message_text = text;
            }
            return;
        }

        //cannot post the same message twice in a row unless at least 5 seconds apart.
        if (text == chat.last_message_text && (Date.now() - chat.last_message_timestamp) / 1000 < 5) {
            return;
        }

        //messages must be less than 255
        if (text.length > 255) {
            alert('Your message is too long. Make it less than 255 characters.');
            if (options.ui) {
                options.ui.message_text = text;
            }
            return;
        }

        chat.last_message_text = text;
        chat.last_message_timestamp = Date.now();

        // don't allow empty messages
        if (text == '') {
            return;
        }

        let message = {
            text : text,
            timestamp : firebase.database.ServerValue.TIMESTAMP,
            type : options.type || 'message',
            user_id : chat.current_user.id,
            name : chat.current_user.name,
        };
        if (options.emote) {
            message.emote = options.emote;
        }
        chat.refs.messages.child(room_id).push(message, function(error) {
            if (error) {
                wing.error('You do not have permission to participate in the chat.');
            }
        });
    };
    chat.focus = function (room_id, timeout) {
        setTimeout(function() {
            const el = document.getElementById('createmessage'+room_id);
            if (el != null) {
                el.focus();
            }
        }, _.defaultTo(timeout, 200));
    };

    /* manage rooms */
    Vue.component('room-list', {
      template : `<div>
        <div class="card border-0 m-0 p-0" :class="{'bg-dark' : color_mode == 'dark', 'bg-light' : color_mode == 'light', 'text-light' : color_mode == 'dark', 'text-dark' : color_mode == 'light'}">
            <div class="row m-0 p-0">
                <div class="col-9 m-0 p-0 card-body" id="rooms">
                    <div class="tab-content">
                        <div style="overflow-y: scroll" class="tab p-3" :class="{'d-none' : current_room != 'settings'}">
                            <h2>Settings</h2>
                            <b-form-group label="Color Mode">
                             <b-form-radio-group
                                                 buttons
                                                 v-model="color_mode"
                                                 :options="color_mode_options"
                                                 @change="save_preference('color_mode')"
                                                  />
                             </b-form-group>

                             <div v-if="bans.length > 0 && chat.current_user.moderator">
                                <h3>Bans</h3>
                                <table class="table table-striped">
                                    <thead>
                                        <tr>
                                            <th>Name</th>
                                            <th>Expires</th>
                                            <th>Lift</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        <tr v-for="ban in bans">
                                            <td>{{ban.user.name}}</td>
                                            <td>{{ban.until|timeago}}</td>
                                            <td><button @click="lift_ban(ban.user)" class="btn btn-warning">Lift Ban</button></td>
                                        </tr>
                                    </tbody>
                                </table>
                             </div>
                        </div>
                        <div style="overflow-y: scroll" class="tab p-3" :class="{'d-none' : current_room != 'create_room'}">
                            <h2>Create Public Room</h2>
                            <p>Everyone will have access to this room and will join automatically to it.</p>
                            <div class="form-control-group">
                                <label for="new_room_name">New Room Name</label>
                                <input type="text" v-model="new_name" class="form-control" maxlength="20">
                                <button class="btn btn-success mt-1" @click="create_public_room()">Create Public Room</button>
                            </div>
                        </div>
                        <div style="height: 100vh; overflow-y: scroll" class="tab p-3" :class="{'d-none' : current_room != 'invites'}">
                            <h2>Pending Invitations</h2>
                            <div v-for="invite in invites" class="mb-5">
                                <div>{{invite.from_user_name}} has invited you to join {{invite.room_name}}</div>
                                <button class="btn btn-success" @click="accept_invite(invite.room_id)">Accept</button>
                                <button class="btn btn-danger" @click="decline_invite(invite.room_id)">Decline</button>
                            </div>
                        </div>
                        <div class="tab" :class="{'d-none' : current_room != room.id}" v-for="room in Object.values(rooms)" :key="room.id">
                            <room-controller @create_private_chat="create_private_room($event)" :color_mode="color_mode" :room="room" @message_added="increment_recent_message_count(room)"></room-controller>
                        </div>
                    </div>
                </div>
                <div class="col-3 p-1 card-header" id="tabs">
                    <div style="height: 100vh; overflow-y: scroll;">
                        <div class="nav flex-column nav-pills" role="tablist" aria-orientation="vertical">
                            <a class="nav-link" :class="{active : current_room == 'settings'}" @click="focus_room('settings')">
                                <div class="p-1 float-left"><i v-b-tooltip.hover.left title="Settings" class="fas fa-sliders-h"></i></div>
                                <div class="p-1 d-none d-sm-inline-block panelname float-left">Settings</div>
                            </a>
                            <a v-if="chat.current_user.moderator" class="nav-link" :class="{active : current_room == 'create_room'}" @click="focus_room('create_room')">
                                <div class="p-1 float-left"><i v-b-tooltip.hover.left title="Create Public Room" class="fas fa-comment-plus"></i></div>
                                <div class="p-1 d-none d-sm-inline-block panelname float-left">Create Public Room</div>
                            </a>
                            <a v-if="invites.length > 0" class="nav-link" :class="{active : current_room == 'invites'}" @click="focus_room('invites')">
                                <div class="p-1 float-left"><i v-b-tooltip.hover.left title="Pending Invitations" class="fas fa-comment-exclamation"></i></div>
                                <div class="p-1 d-none d-sm-inline-block panelname float-left">Pending Invitations</div>
                                <div class="p-1 mt-1 badge badge-danger float-left">{{invites.length}}</div>
                            </a>
                            <a class="nav-link" :class="{active : current_room == room.id}" v-for="room in orderBy(Object.values(rooms),'name')" :key="room.id" @click="focus_room(room.id)">
                                <div class="p-1 float-left"><i v-b-tooltip.hover.left :title="room.name" class="fas" :class="{'fa-comments' : room.type == 'official', 'fa-comment-lines' : room.type == 'public', 'fa-comment-smile' : room.type == 'private'}"></i></div>
                                <div class="p-1 d-none d-sm-inline-block roomname float-left">{{room.name}}</div>
                                <div class="p-1 mt-1 badge badge-secondary float-left" v-if="room.recent_message_count > 0">{{room.recent_message_count}}</div>
                                <div class="float-right ml-2" v-if="room.type != 'official'">
                                    <span title="Remove Room" @click="remove_room(room.id)" v-if="chat.current_user.id == room.created_by || chat.current_user.moderator"><i class="fas fa-trash-alt"></i></span>
                                    <span class="ml-1" title="Leave Room" @click="leave_room(room.id)"><i class="fas fa-sign-out-alt"></i></span>
                                </div>
                            </a>
                        </div>
                    </div>
                </div>
            </div>
        </div>
      </div>`,
      data() {
          return {
              new_name : '',
              rooms : {},
              current_room : null,
              official_room : null,
              bans : [],
              invites : [],
              color_mode : _.defaultTo(localStorage.getItem('chat.color_mode'),'light'),
              color_mode_options : [
                  { text : 'Light', value : 'light'},
                  { text : 'Dark', value : 'dark'},
              ],
          }
      },
      methods : {
          save_preference(field) {
              const self = this;
              setTimeout(function() {
                  localStorage.setItem('chat.color_mode',self.color_mode);
              }, 200);
          },
          get_room(id) {
              return chat.refs.rooms.child(id).once('value');
          },
          join_room(id) {
              const self = this;
              self.get_room(id)
              .then(function(snapshot) {
                  const room = snapshot.val();
                  if (room == null || self.rooms[room.id]) { // don't join a room we're already in
                      return;
                  }
                  room.recent_message_count = 0;
                  Vue.set(self.rooms, room.id, room);
                  chat.refs.current_user.child('rooms/'+room.id).update({name : room.name, id : room.id});
              })
              .catch(function(error) {
                  console.error(error);
              });
          },
          remove_ban_from_list(user_id) {
              const self = this;
              for (var i = 0, len = self.bans.length; i < len; i++) {
                  if (self.bans[i].user.id === user_id) {
                      self.bans.splice(i,1);
                      break;
                  }
              }
          },
          lift_ban(user) {
              const self = this;
              chat.refs.bans.child(user.id).remove(function(error) {
                  wing.info('Ban lifted.');
                  self.remove_ban_from_list(user.id);
              });
          },
          create_public_room() {
              this.create_room(this.new_name, { type : 'public' });
              this.new_name = '';
          },
          create_private_room(user_id) {
              const self = this;
              let users = {};
              users[user_id] = true;
              users[chat.current_user.id] = true;
              chat.lookup_user(user_id, function(user) {
                  const name = user.name + ' + ' + chat.current_user.name;
                  self.create_room(name, {
                      type : 'private',
                      authorized : users,
                      on_create : function(room_id) {
                          chat.send_invite(user_id, room_id, name);
                          self.join_room(room_id);
                      },
                  });
              })
          },
          create_room (name, options) {
               const self = this;
               if (typeof name == 'undefined' || name.length < 3) {
                    wing.error('You must specify a name between 3 characters to create a room.');
                    return;
               }
               if (typeof options != 'object') {
                    options = {};
               }
               const id = chat.refs.rooms.push().key;
               let new_room = {
                    id : id,
                    name : name,
                    type : options.type || 'private',
                    created_by : chat.current_user.id,
                    authorized : typeof options.authorized == 'object' ? options.authorized : { },
               };
               new_room.authorized[chat.current_user.id] = true;
               chat.refs.rooms.child(id).update(new_room);
               if (typeof options.on_create != 'undefined') {
                   options.on_create(id);
               }

               // select the new tab
               self.focus_room(id);
          },
          increment_recent_message_count(room) {
              if (room.id != this.current_room)
              room.recent_message_count++;
          },
          find_current_room() {
              this.rooms[self.current_room];
          },
          focus_room(id) {
              const self = this;
              self.current_room = id;
              if (id in self.rooms) {
                  self.rooms[id].recent_message_count = 0;
              }
              chat.focus(id);
          },
          leave_room(id) {
              const self = this;
              Vue.delete(self.rooms, id);
              chat.add_message(id, 'has left.', {type : 'notice'});
              chat.refs.current_user.child('rooms/'+id).remove();
              setTimeout(function() {
                  self.focus_room(self.official_room);
              }, 200);
          },
          remove_room(id) {
              const self = this;
              chat.refs.messages.child(id).remove();
              chat.refs.rooms.child(id).remove();
          },
          remove_invite(room_id){
              const self = this;
              chat.refs.current_user_invites.child(room_id).remove();
              for (var i = 0, len = self.invites.length; i < len; i++) {
                  if (self.invites[i].room_id === room_id) {
                      self.invites.splice(i,1);
                      break;
                  }
              }
          },
          accept_invite(room_id) {
              const self = this;
              self.remove_invite(room_id);
              self.join_room(room_id);
              chat.add_message(room_id, 'has joined.', {type : 'notice'});
              self.focus_room(room_id);
          },
          decline_invite(room_id) {
              const self = this;
              self.remove_invite(room_id);
          },
      },
      mounted() {
          const self = this;

          /* join rooms i'm already in */
          chat.refs.current_user.child('rooms').once('value')
          .then(function(snapshot) {
              const rooms = snapshot.val();
              for (var id in rooms) {
                 self.join_room(id);
              }
          })
          .catch(function(error) {
              console.error(error);
          });

          /* automatically join official and public rooms as they are added */
          chat.refs.rooms.on('child_added', function(snapshot) {
              const room = snapshot.val();
              if (room.type == 'official' || room.type == 'public') {
                  self.join_room(room.id);
                  if (room.type == 'official') {
                      self.official_room = room.id;
                      self.focus_room(room.id);
                  }
              }
          });

          /* automatically leave rooms that go away */
          chat.refs.rooms.on('child_removed', function(snapshot) {
              const room = snapshot.val();
              self.leave_room(room.id);
          });

          /* display invitations */
          chat.refs.current_user_invites.on('child_added', function(snapshot) {
              self.invites.push(snapshot.val());
          });

          /* update rooms when changes are made */
          chat.refs.rooms.on('child_changed', function(snapshot) {
              const room = snapshot.val();
              Vue.set(self.rooms, room.id, room);
          });

          /* enumerate bans */
          if (chat.current_user.moderator) {
              chat.refs.bans.on('child_added', function(snapshot) {
                  chat.lookup_user(snapshot.key, function(user) {
                      self.bans.push({
                          user : user,
                          until : snapshot.val(),
                      });
                  });
              });
              chat.refs.bans.on('child_removed', function(snapshot) {
                  self.remove_ban_from_list(snapshot.key);
              });
          }

      },
      beforeDestroy() {
          chat.refs.rooms.off('child_added');
          chat.refs.rooms.off('child_removed');
          chat.refs.current_user_invites.off('child_added');
          chat.refs.rooms.off('child_changed');
          if (chat.current_user.moderator) {
              chat.refs.bans.off('child_added');
          }
      }
    });

    /* view a room */
    Vue.component('room-controller', {
      template : `
        <div><div style="height: 100vh">
            <message-list :color_mode="color_mode" @create_private_chat="$emit('create_private_chat',$event)" :room="room" class="message-list" style="height:calc(100vh - 70px); overflow-y: scroll"></message-list>
            <textarea :class="colors()" :id="'createmessage'+room.id" autofocus="true" v-model="message_text" @keydown="handle_keystroke($event)" placeholder="say something or type /help for options" class="border-0 position-absolute w-100 p-2" style="resize: none; bottom: 0; left: 0; height='70px';"></textarea>
        </div></div>`,
      props: ['room','color_mode'],
      data() {
          return {
              last_message_timestamp : Date.now(),
              last_message_text : '',
              message_text : '',
              autoscroll : true,
          }
      },
      methods : {
          colors() {
             if (this.color_mode == 'light') {
                 return 'bg-white text-dark';
             }
             else {
                 return 'bg-secondary text-white';
             }
          },
          handle_keystroke(event) {
              const self = this;
              if (event.key == 'Enter') {
                  if (event.shiftKey) {
                      // allow enter to register
                  }
                  else {
                      event.preventDefault();
                      self.create_message();
                  }
              }
          },
          create_message () {
              const self = this;
              const text = self.message_text.trim();
              self.message_text = '';

              /* process commands */
              if (text.match(/^\/(.*)$/)) {
                  self.$emit('process_command', text);
                  self.scroll_to_end();
              }
              /* post a message */
              else {
                  chat.add_message(self.room.id, text, {ui : self});
              }
          },
          scroll_to_end: function() {
              const self = this;
              setTimeout(function() {
                  const container = self.$el.querySelector(".message-list");
                  container.scrollTop = container.scrollHeight;
              }, 200)
          },
          conditional_scroll_to_end: function() {
              const self = this;
              if (document.activeElement.id == 'createmessage'+self.room.id) {
                  self.scroll_to_end();
              }
          },
      },
      mounted() {
          const self = this;

          /* scroll to end of messages if they resize the window */
          self.$nextTick(() => {
              window.addEventListener('resize', () => {
                  self.scroll_to_end();
              });
          });

          /* fire event to increment recent message counts */
          chat.refs.messages.child(self.room.id).on('child_added', function(snapshot) {
              self.$emit('message_added',self.room.id);
              self.conditional_scroll_to_end();
          });

          document.getElementById('createmessage'+self.room.id).addEventListener('focus', self.scroll_to_end);

      }
    });

    /* a room's message list */
    Vue.component('message-list', {
      template : `<div class="p-3">
            <h3>{{room.name}}</h3>
            <template v-for="message in messages">
                <template v-if="message.type != 'system'"><message-control :color_mode="color_mode" @create_private_chat="$emit('create_private_chat',$event)" :message="message" :room="room" :id="message.id"></message-control></template>
                <div v-else v-html="message.text" class="m-5"></div>
            </template>
        </div>`,
      props: ['room','color_mode'],
      data() {
          return { messages : [], limit_message_count : 200 };
      },
      methods: {
          add_system_message(message) {
              this.messages.push({
                  type : 'system',
                  text : message,
                  timestamp : Date.now()
              });
          },
          process_command(text) {
                const self = this;
                for (var i in chat.commands) {
                    var command = chat.commands[i];
                    if (text.match(command.match)) {
                        if (command.moderator_only && !chat.current_user.moderator) {
                            continue;
                        }
                        command.func(text, self);
                    }
                }
          },
      },
      created() {
          const self = this;
          self.$parent.$on('process_command',self.process_command);

          /* new message added */
          chat.refs.messages.child(self.room.id).limitToLast(self.limit_message_count).on('child_added', function(snapshot) {
              const message = snapshot.val();
              message.id = snapshot.key;
              message.like_count = 0;
              if (self.messages.length == 0 || self.messages[self.messages.length - 1].timestamp - 1000 < message.timestamp ) { // stops old messages from popping in when messages are deleted
                  self.messages.push(message);
              }
              else {
                  console.info('stopped an old message from being appended');
              }
          });

          /* message deleted */
          chat.refs.messages.child(self.room.id).on('child_removed', function(snapshot) {
              const el = document.getElementById(snapshot.key);
              el.parentNode.removeChild(el);
          });

          /* increment like counter */
          chat.refs.likes.child(self.room.id).limitToLast(200).on('child_added', function(snapshot) {
              const like = snapshot.val();
              for (var i in self.messages) {
                  if (self.messages[i].id == like.message_id) {
                      self.messages[i].like_count++;
                      break;
                  }
              }
          });
      }
    });

    /* an individual message */
    Vue.component('message-control', {
      template : `<div class="mb-2">
            <b-media v-if="message.type != 'notice'">
                <b-img v-if="message.type == 'message'" slot="aside" :src="user.avatar_uri" width="50" height="50" alt="placeholder" class="rounded d-none d-sm-block" />
                <div :class="{'text-center' : (message.type == 'emote')}">

                    <a :href="user.profile_uri" target="_new" :class="{'text-secondary' : !user.moderator, 'text-success' : user.staff, 'text-info' : user.moderator && !user.staff}">{{user.name}} <small v-if="user.badge" :style="'color:'+badge_color(user)">{{user.badge}}</small></a>
                    <span v-if="message.type == 'emote'" class="font-italic" v-html="filter_content(message.text)"></span>

                    <small v-if="message.type == 'message'" class="ml-3">{{message.timestamp | moment('h:mm a')}}</small>

                    <b-dropdown class="ml-3" title="Special Actions" size="sm" variant="link" no-caret>
                        <template slot="button-content">
                            <i class="fas fa-ellipsis-h"></i>
                        </template>
                        <b-dropdown-item v-if="chat.current_user.id != message.user_id" @click="like_message(message.id)"><i class="fas fa-heart"></i> Like Message</b-dropdown-item>
                        <b-dropdown-item v-if="chat.current_user.id != message.user_id" @click="$emit('create_private_chat',message.user_id)"><i class="fas fa-comment-smile"></i> Private Message</b-dropdown-item>
                        <b-dropdown-divider v-if="chat.current_user.id != message.user_id"></b-dropdown-divider>
                        <b-dropdown-item v-if="chat.current_user.moderator && chat.current_user.id != message.user_id" @click="warn_user(user)"><i class="fas fa-exclamation-triangle"></i> Warn</b-dropdown-item>
                        <b-dropdown-item v-if="chat.current_user.moderator && chat.current_user.id != message.user_id" @click="ban_user(user, 60 * 60 * 1000)"><i class="fal fa-ban"></i> Ban for 1 hour</b-dropdown-item>
                        <b-dropdown-item v-if="chat.current_user.moderator && chat.current_user.id != message.user_id" @click="ban_user(user, 60 * 60 * 1000 * 24)"><i class="far fa-ban"></i> Ban for 1 day</b-dropdown-item>
                        <b-dropdown-item v-if="chat.current_user.moderator && chat.current_user.id != message.user_id" @click="ban_user(user, 60 * 60 * 1000 * 24 * 365)"><i class="fas fa-ban"></i> Ban for 1 year</b-dropdown-item>
                        <b-dropdown-divider v-if="chat.current_user.moderator && chat.current_user.id != message.user_id"></b-dropdown-divider>
                        <b-dropdown-item v-if="chat.current_user.moderator || message.user_id == chat.current_user.id" title="delete message" @click="delete_message(message)"><i class="fas fa-trash-alt"></i> Delete</b-dropdown-item>
                    </b-dropdown>
                </div>
                <div v-if="message.type == 'message'" v-html="filter_content(message.text)"></div>
                <div class="text-danger" :class="{'text-center' : (message.type == 'emote')}">
                    <i @click="like_message(message.id)" class="fas fa-heart mr-1" v-for="index in message.like_count"></i>
                </div>
            </b-media>
            <div v-else class="border border-secondary p-3 rounded" :class="colors()">
                <i v-if="chat.current_user.moderator" class="fas fa-trash-alt float-right" title="delete message" @click="delete_message(message)"></i>
                <a :href="user.profile_uri" target="_new" :class="{'text-secondary' : !user.moderator, 'text-success' : user.staff, 'text-info' : user.moderator && !user.staff}">{{user.name}}</a> {{message.text}}
            </div>
        </div>`,
      props: ['message','room','color_mode'],
      data() {
          return {
              user : {},
          }
      },
      methods : {
          badge_color(user) {
              if (user.badge_color == 'green') {
                  return '#1cc500';
              }
              else if (user.badge_color == 'blue') {
                  return '#0066ff';
              }
              else if (user.badge_color == 'red') {
                  return '#cc0000';
              }
              else if (user.badge_color == 'yellow') {
                  return '#ddce22';
              }
              else if (user.badge_color == 'orange') {
                  return '#ff9c00';
              }
              else if (user.badge_color == 'purple') {
                  return '#9c00ff';
              }
              else {
                  return '#9999aa';
              }
          },
          colors() {
             if (this.color_mode == 'light') {
                 return 'bg-light text-dark';
             }
             else {
                 return 'bg-dark text-white';
             }
          },
          filter_content(html) {
              // remove html
              const doc = new DOMParser().parseFromString(html, 'text/html');
              let out = doc.body.textContent || "";

              // carriage returns
              out = out.replace(/\n/g, '<br>');

              // render icons
              out = out.replace(/(\:\w+\:)/g,function(match, offset, string){
                  const fixed = match.substring(1,match.length - 1);
                  const classname = chat.icons[fixed];
                  if (typeof classname == 'undefined') {
                      return match;
                  }
                  else {
                      return '<i class="font-size-200 fas '+classname+'"></i>';
                  }
              });

              // link links
              return linkifyHtml(out, {
                  format: {
                    url: function (value) {
                      return value.length > 50 ? value.slice(0, 35) + '…' : value
                    },
                    target: {
                       url: '_blank'
                     },
                  }
              });
          },
          like_message(message_id) {
              const self = this;
              chat.refs.likes.child(self.room.id).push({ user_id : chat.current_user.id, message_id : message_id});
              chat.focus(self.room.id, 1);
          },
          delete_message(message) {
              const self = this;
              if (confirm('Are you sure you wish to delete this message?')) {
                  chat.refs.messages.child(self.room.id).child(message.id).remove();
                  chat.focus(self.room.id, 1);
              }
          },
          ban_user(user, duration) {
              const self = this;
              const timestamp = Date.now() + duration;
              chat.refs.bans.child(user.id).set(timestamp, function(error) {
                  const until = wing.parse_date(timestamp).fromNow();
                  chat.add_message(self.room.id, 'has banned '+user.name+'. The ban will be lifted '+until+'.', {type : 'notice'});
              });
              chat.focus(self.room.id, 1);
          },
          warn_user(user) {
              const self = this;
              chat.add_message(self.room.id, 'issued a warning to '+user.name+'.', {type : 'notice'});
              chat.focus(self.room.id, 1);
          }
      },
      created() {
          const self = this;
          chat.lookup_user(self.message.user_id, function(user) {
              self.user = user;
          });
      }
    });

    /* sign in */
    chat.firebase.auth().signInWithCustomToken(config.firebase.jwt)
    .then(
        auth => {
            chat.refs.current_user.update(chat.current_user, function(error) {

                const start_app = function() {
                    /* the base app */
                     new Vue({
                        el : '#chat',
                    });
                }

                if (chat.current_user.moderator) {
                    chat.refs.moderators.child(chat.current_user.id).update(chat.current_user, function(error) {
                        start_app();
                    });
                }
                else {
                    start_app();
                }

            });
        }
    )
    .catch(function(error) {
        console.error("Firebase login failed!", error);
    });
}

(function() {
  var Bot, bartender, util, _un;
  Bot = require('ttapi');
  _un = require('underscore');
  util = require('util');
  bartender = function(userAuth, selfId, roomId) {
    var bot, cmd_drinks, command, commands, plural, random_select, roomUsernames, roomUsers, special_drinks;
    if (!userAuth) {
      util.puts("User auth token required");
      util.exit;
    }
    if (!selfId) {
      util.puts("User id token required");
      util.exit;
    }
    if (!roomId) {
      util.puts("Room id token required");
      util.exit;
    }
    bot = new Bot(userAuth, selfId, roomId);
    roomUsernames = {};
    roomUsers = {};
    plural = function(count) {
      if (count === 1) {
        return 's';
      } else {
        return '';
      }
    };
    random_select = function(list) {
      return list[Math.floor(Math.random() * list.length)];
    };
    special_drinks = {
      "beer": "Tap specials today are the Rogue Dead Guy Ale and the Pyramid Hefeweizen (or do you drink Bud Light?)",
      "wine": "Here, try some of our finest Chardonnay!",
      "vodka": "One double of Stoli on the rocks, coming right up!",
      "scotch": "/me pours a double of Laphroaig 16",
      "gin & tonic": "Here's a Gin & Tonic! Would you like some lime in that?",
      "amf": "Say 'Adios', motherf*cker!",
      "4loko": "Are you ready to get SLAMMED?",
      "natty": "Alright, one 'beer' coming right up...",
      "coors": "CHUG! CHUG! CHUG! CHUG!",
      "redbull & vodka": "Party it up in hurrrrrr",
      "soda": ["Mmm, nothing like a Coca-Cola", "Why not take a break and have some Sprite", "OK, here's a Dr. Pepper"],
      "pop": "Are you sure you didn't mean a SODA?",
      "keg": "Are you sure that isn't a bit much for one person?"
    };
    bot.on("registered", function(data) {
      var user, _i, _len, _ref, _results;
      if (data.user[0].userid === selfId) {
        bot.roomInfo(function(data) {
          var user, _i, _len, _ref, _results;
          _ref = data.users;
          _results = [];
          for (_i = 0, _len = _ref.length; _i < _len; _i++) {
            user = _ref[_i];
            roomUsernames[user.name] = user;
            _results.push(roomUsers[user.userid] = user);
          }
          return _results;
        });
      }
      _ref = data.user;
      _results = [];
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        user = _ref[_i];
        roomUsernames[user.name] = user;
        _results.push(roomUsers[user.userid] = user);
      }
      return _results;
    });
    cmd_drinks = function(user, args) {
      var lcDrink, msgs, selection;
      msgs = ["This party is bumping! Drinks all around!", "Hey " + user.name + ", here's a little something to get you rocking!", "Martini, shaken, not stirred.", "Scotch neat", "Jager bombs! Jager bombs!", "Hey " + user.name + ", I think you might have had a little too much to drink", "Tequila sunrise for you", "Here's an Adios Mother F***er. Say 'adios!'", "We've got a great selection of beer here.", "A cape cod huh. Is it that time of the month?", "Here's some hard cider", "" + user.name + ", do you need me to call a cab", "Ah a Belgian. How about the St. Bernardus 12", "Irish Car Bomb for you", "Hey " + user.name + ", here's a White Russian", "Some wine, perhaps?", "Here's a Flaming Doctor Pepper!", "Margarita coming right up", "We've got a great selection on this bus!", "/me ices " + user.name, "/me wipes a glass", "/me cuts a lime"];
      lcDrink = args.toLowerCase();
      if (lcDrink in special_drinks) {
        selection = special_drinks[lcDrink];
        if (typeof selection === "object") {
          bot.speak(random_select(selection));
        } else {
          bot.speak(selection);
        }
      } else {
        bot.speak(random_select(msgs));
      }
      return bot.vote("up");
    };
    commands = [
      {
        cmd: /^\/drinks?$/,
        fn: cmd_drinks,
        help: "drinks"
      }
    ];
    bartender.commands = commands;
    command = function(data) {
      var args, cmd, cmd_pat, match;
      cmd_pat = /^([^\s]+?)(\s+([^\s]+.+?))?\s*$/;
      cmd = "";
      args = "";
      if (match = cmd_pat.exec(data.text)) {
        cmd = match[1].toLowerCase();
        args = match[3] || "";
      }
      return [cmd, args];
    };
    return bot.on("speak", function(data) {
      var args, cmd_matches, cmd_txt, resolved_cmd, user, _ref;
      _ref = command(data), cmd_txt = _ref[0], args = _ref[1];
      user = roomUsers[data.userid];
      cmd_matches = function(entry) {
        if (typeof entry.cmd === "string" && entry.cmd === cmd_txt) {
          return true;
        }
        if (typeof entry.cmd === "function" && entry.cmd.test(cmd_txt)) {
          return true;
        }
      };
      resolved_cmd = _un.detect(commands, cmd_matches);
      if (resolved_cmd) {
        return resolved_cmd.fn(user, args);
      }
    });
  };
  exports.bartender = bartender;
}).call(this);

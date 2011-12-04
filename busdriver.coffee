Bot = require 'ttapi'
irc = require 'irc'
_ = require 'underscore'
util = require 'util'
readline = require 'readline'
mongodb = require('mongodb')

greet = require './greetings'

# Constants
SECOND = 1000
MINUTE = 60*SECOND
HOUR = 60 * MINUTE
DAY = 24 * HOUR
WEEK = 7 * DAY

# Utility functions
plural = (count) ->
  if count == 1
    's'
  else
    ''

now = -> new Date()

elapsed = (date) ->
  if date
    new Date().getTime() - date.getTime()
  else
    -1

random_select: (list) ->
  list[Math.floor(Math.random()*list.length)]

countdown = (callback, it, time) ->
  if time > 0
    it(time)
    delay = -> countdown(callback, it, time-1)
    setTimeout(delay, 1000)
  else
    callback()

delay_countdown = (callback, it, time) ->
  delay = -> countdown(callback, it, time)
  
  setTimeout(delay, 1000)

norm = (text) ->
  text.trim().toLowerCase()

is_uid = (uid) ->
  uid and uid.length == 24

to_positive_int = (arg) ->
  result = parseInt(arg)
  
  if not isNaN(result) and result > 0
    result

pretty_int = (value, unit) ->
  if unit?
    "#{value} #{unit}#{plural(value)}"
  else
    "#{value}"

to_bool = (arg) ->
  arg = norm(arg)
  
  arg = arg is "true" or arg is "on" or arg is "yes"

class BusDriver
  # State dependent utility functions
  is_vip: (uid) ->
    uid of @vips
  
  is_allowed: (uid) ->
    uid of @allowed
      
  update_name: (name, uid) ->
    @roomUsernames[norm(name)] = uid
    
    if uid of @roomUsers
      @roomUsers[uid].name = name
  
  update_idle: (uid) ->
    @lastActivity[uid] = now()
    if uid of @warnedDjs
      delete @warnedDjs[uid]
  
  get_by_name: (name) ->
    name = norm(name)
    if name of @roomUsernames
      @roomUsers[@roomUsernames[name]]
  
  get_uid: (name) ->
    @roomUsernames[norm(name)]

  get_dj: (name) ->
    uid = @get_uid(name)
    if uid of @djSongCount
      return uid
  
  # Configuration
  config_props:
    max_songs: {default: 3, unit: "song", format: "+int", name: "Song limit"}
    camp_songs: {default: 2, unit: "song", format: "+int", name: "DJ autoescort songs"} # How much tolerance we have before we just escort
    wait_songs: {default: 3, unit: "song", format: "+int", name: "DJ naughty corner songs"}
    wait_songs_day: {default: 3, unit: "song", format: "+int", name: "DJ naughty corner songs for day time"}
    wait_songs_night: {default: 1, unit: "song", format: "+int", name: "DJ naughty corner songs for night time"}
    wait_time: {default: 15, unit: "minute", format: "+int", name: "DJ naughty corner time"}
    moderate_dj_min: {default: 3, unit: "dj", format: "+int", name: "Enforced rules DJ minimum"} # Minimum number of DJs to activate reup modding
    dj_warn_time: {default: 11, unit: "minute", format: "+int", name: "AFK DJ warning time"}
    dj_escort_time: {default: 15, unit: "minute", format: "+int", name: "AFK DJ escort time"}
    mode: {default: NORMAL_MODE, format: "room_mode", name: "room mode", set: ((value) -> room_mode = value), get: -> room_mode}
    debug: {default: off, format: "onoff", name: "Command line debug", set: ((value) -> debug_on = value), get: -> debug_on}
    rules_link: {default: "http://bit.ly/thepartybus", name: "Rules link"}
    greetings: {default: true, format: "onoff", name: "Greetings"}
    capacity_boot: {default: true, format: "onoff", name: "Boot at capacity"}
  
  to_room_mode: (arg) ->
    arg = norm(arg)
    
    if args is "vips" or args is "vip"
      @bot.speak "It's a VIP party in here! VIPs (and mods) only on deck!"
      VIP_MODE
    else if args is "battle"
      @bot.speak "Ready to BATTLE?!!!"
      BATTLE_MODE
    else
      @bot.speak "Back to the ho-hum. FFA, #{@get_config('max_songs')} song limit, #{@get_config('wait_songs')} wait time between sets"
      NORMAL_MODE
  
  pretty_room_mode: (value) ->
    if value is VIP_MODE
      @bot.speak "It's a VIP party in here! VIPs (and mods) only on deck!"
    else if value is BATTLE_MODE
      @bot.speak "Ready to BATTLE?!!!"
    else
      @bot.speak "The ho-hum. FFA, #{@get_config('max_songs')} song limit, #{@get_config('wait_songs')} wait time between sets"
      
  config_format:
    "+int": {to: to_positive_int, pretty: pretty_int}
    "onoff": {to: to_bool, pretty: (value) -> if value then "on" else "off"}
    "room_mode": {to: @to_room_mode, pretty: @pretty_room_mode}
  
  get_config: (x) ->    
    if x of config_props
      props = @config_props[x]
    
      result = @config[x] ? props.default
  
  set_config: (x, value) ->
    if x of @config_props
      props = @config_props[x]
      
      value = (if props.format? and (to = @config_format[props.format]?.to)? then to(value) else value) ? props.default
      
      @config[x] = value
      
      @db.collection 'rooms', (err, col)->
        criteria =
          roomId: @roomId
        modifications = 
          "$set": {}
        
        modifications["$set"]["config.#{x}"] = value
        
        col.update criteria, modifications, {upsert: true}
  
  constructor: (options) ->
    if not options.userAuth
      util.puts("User auth token required")
      util.exit
    
    if not options.userId
      util.puts("User id token required")
      util.exit
    
    if not options.roomId
      util.puts("Room id token required")
      util.exit

    @userId = options.userId
    @roomId = options.roomId
    
    # Variables
    @songName = ""
    @album = ""
    @upVotes = 0
    @downVotes = 0
    @lastScore = ""
    
    @roomUsernames = {}
    @roomUsers = {}
    @active = {}
    @roomUsersLeft = {}
    @joinedUsers = {}
    joinedTimeout = null
    @lastActivity = {}
    JOINED_DELAY = 15000
    @djSongCount = {}
    @campingDjs = {}
    @mods = {}
    @vips = {}
    @allowed = {}
    @currentDj = undefined
    @lastDj = undefined
    @warnedDjs = {}
    queueEnabled = false
    @selfModerator = false
    @permabanned = {}
    enabled = true
    @boost = false
    
    @chat_enabled = false
    
    @pastDjSongCount = {}
    
    @db_ready = false
    
    db_connection = new mongodb.Db 'TheBusDriver', (new mongodb.Server '127.0.0.1', 27017, {})
    db_connection.open (err, db)->
      if err
        util.puts err
      else
        @db = db
        @db_ready = true
    
    @bot = new Bot options.userAuth, options.userId, options.roomId

    options.excluded_mods = options.excluded_mods or []
    options.ircHandle = options.ircHandle or "BusDriver"
    
    # Constants
    NORMAL_MODE = 0
    VIP_MODE = 1
    BATTLE_MODE = 2
    
    @room_mode = NORMAL_MODE
    @debug_on = false
    
    @config = {}
    
    @db.collection 'rooms', (err, col)->
      criteria =
        roomId: options.roomId
      col.findOne criteria, (err, doc) ->
        if doc isnt null
          for x, value of doc.config
            @set_config(x, value)

    tracked_actions =
      "hearts"
      "hugs"
    
    actions = {}
    
    for action in tracked_actions
      actions[action] = {}
            
    #ircClient = new irc.Client options.ircServer, options.ircHandle, 
    #  channels: [options.ircChan]
    
    #ircClient.addListener "message", (from, to, message)->
      # irc handling
      # no custom commands yet
    
    debug = (txt) ->
      if debug_on
        util.puts txt
    
    process_votelog = (votelog) ->
      # This might work... not sure what the votelog is
      for [uid, vote] in votelog
        if uid isnt ""
          update_idle(uid)
          
          if vote is "down"
            lamers[uid] = true
          else
            delete lamers[uid]
    
    roomInfo = (callback) ->
      @bot.roomInfo (data) ->
        @currentDj = if data.room.metadata.current_dj? then @roomUsers[data.room.metadata.current_dj]
      
        # Initialize song
        if data.room.metadata.current_song
          @songName = data.room.metadata.current_song.metadata.song
          @album = data.room.metadata.current_song.metadata.album
          @upVotes = data.room.metadata.upvotes
          @downVotes = data.room.metadata.downvotes
      
        process_votelog data.room.metadata.votelog
        
        callback data
    
    # Count songs DJs have waited for
    djWaitCount = {}
    
    is_mod = (userId) ->
      userId of @mods
    
    is_owner = (userId) ->
      _.include(options.owners, userId)

    escort = (uid) ->
      @bot.remDj(uid)
      
      delay = -> @bot.remDj(uid)
      
      setTimeout delay, 500
    
    @bot.on "update_votes", (data)->
      @upVotes = data.room.metadata.upvotes
      @downVotes = data.room.metadata.downvotes

      if @songName is ""
        roomInfo (data)->
          @songName = data.room.metadata.current_song.metadata.song
      
      # This might work... not sure what the votelog is
      process_votelog data.room.metadata.votelog

    @bot.on "newsong", (data)->
      if @songName isnt ""
          @bot.speak "#{@songName} - [#{@upVotes}] Awesomes, [#{@downVotes}] Lames"
          @lastScore = "#{@songName} - [#{@upVotes}] Awesomes, [#{@downVotes}] Lames"
      
      # Reset vote count
      @upVotes = data.room.metadata.upvotes
      @downVotes = data.room.metadata.downvotes
      
      lamers = []
      
      @songName = data.room.metadata.current_song.metadata.song
      @currentDj = @roomUsers[data.room.metadata.current_dj]

      if @currentDj.userid of @djSongCount
        @djSongCount[@currentDj.userid]++
      else
        @djSongCount[@currentDj.userid] = 1
      
      @db.collection 'djs', (err, col)->
        criteria =
          'userInfo.userid': @currentDj.userid
        modifications =
          '$set':
            'userInfo': @currentDj
            'onstage': true
            'songs': @djSongCount[@currentDj.userid]
        col.update criteria, modifications, {upsert: true}

      if room_mode is NORMAL_MODE
        # Only mod if there are some minimum amount of DJs
        if enabled and _.keys(@djSongCount).length >= @get_config('moderate_dj_min')
          escorted = {}
          
          # Escort DJs that haven't gotten off!
          for dj in _.keys(@campingDjs)
            @campingDjs[dj]++
            
            if dj not of @vips and @selfModerator and @campingDjs[dj] >= @get_config('camp_songs')
              # Escort off stage
              escort(dj)
              escorted[dj] = true
          
          if @lastDj? and @lastDj.userid not of escorted and @lastDj.userid not of @vips and @djSongCount[@lastDj.user] >= @get_config('max_songs')
            @bot.speak "#{@lastDj.name}, you've played #{@djSongCount[@lastDj.userid]} songs already! Let somebody else get on the decks!"
            
            if @lastDj.userid not of @campingDjs
              @campingDjs[@lastDj.userid] = 0
        
        for dj in _.keys(djWaitCount)
          djWaitCount[dj]++
          
          # Remove from timeout list if the DJ has waited long enough
          if djWaitCount[dj] >= @get_config('wait_songs')
            delete djWaitCount[dj]
            delete @pastDjSongCount[dj]
      # else if room_mode is BATTLE_MODE
      
      # Save DJ
      @lastDj = @currentDj
    
    # Time to wait before considering a rejoining user to have actually come back
    REJOIN_MESSAGE_WAIT_TIME = 5000

    greetings = greet.greetings  
    
    get_greeting = (user) ->
      greeting = null
    
      if user.name of greetings
        greeting = greetings[user.name]
      else if user.userid of greetings
        greeting = greetings[user.userid]
      
      if greeting
        if typeof greeting is "function"
          greeting = greeting(user)
        return greeting
    
    heartbeat = ->
      # Escort AFK DJs
      for uid in _.keys(@djSongCount)
        if uid of @lastActivity
          idle = elapsed(@lastActivity[uid])
          
          if idle > @get_config('dj_warn_time') * MINUTE and uid not of @warnedDjs
            @bot.speak "#{@roomUsers[uid].name}, no falling asleep on deck!"
            @warnedDjs[uid] = true
          if idle > @get_config('dj_escort_time') * MINUTE
            if uid isnt @currentDj?.userid
              escort(uid)
        else
          @lastActivity[uid] = now()
    
    setInterval heartbeat, 1000
    
    update_user = (user) ->
      update_name(user.name, user.userid)
      @roomUsers[user.userid] = user
      
      @db.collection 'users', (err, col)->
        criteria =
          'userInfo.userid': user.userid
        modifications =
          '$set':
            'userInfo': user
        col.update criteria, modifications, {upsert: true}
    
    register = (user) ->
      update_user(user)
      @active[user.userid] = true
      update_idle(user.userid)
    
    @bot.on "registered", (data) ->
      if data.user[0].userid is @userId
        # We just joined, initialize things
        @db.collection 'users', (err, col)->
          col.find {}, (err, cursor) ->
            cursor.each (err,doc)->
              if doc isnt null
                if doc.vip
                  @vips[doc.userInfo.userid] = doc.userInfo
                
                if doc.allowed
                  @allowed[doc.userInfo.userid] = doc.userInfo
                
                if doc.userInfo.userid not of @roomUsers
                  update_user(doc.userInfo)
          
          roomInfo (data) ->
            # Initialize users
            _.map(data.users, register)
            
            # Initialize dj counts
            for uid in data.room.metadata.djs
              @djSongCount[uid] = 0
            
            if @currentDj? and @currentDj.userId of @roomUsers
              @djSongCount[@currentDj.userid] = 1
              
              @lastDj = @roomUsers[@currentDj.userid]
            
            # Check if we are moderator
            @selfModerator = _.any(data.room.metadata.moderator_id, (id) -> id is @userId)
            
            for modId in data.room.metadata.moderator_id
              @mods[modId] = true
      
      _.map(data.user, register)

      user = data.user[0]
      
      if user.userid of @permabanned
        if @selfModerator
          @bot.bootUser(user.userid, @permabanned[user.userid])
          return
        else
          @bot.speak "I can't boot you, #{user.name}, but you've been banned for #{@permabanned[user.userid]}"
      
      # Only say hello to people that have left more than REJOIN_MESSAGE_WAIT_TIME ago
      if @get_config('greetings') and user.userid isnt @userId and (not @roomUsersLeft[user.userid] or now().getTime() - @roomUsersLeft[user.userid].getTime() > REJOIN_MESSAGE_WAIT_TIME)
        if greeting = get_greeting(user)
          delay = ()->
            @bot.speak greeting
          
          setTimeout delay, 5000
        else if user.userid of @vips
          delay = ()->
            @bot.speak "Welcome #{user.name}, we have a VIP aboard the PARTY BUS!"

          setTimeout delay, 5000
        else if user.acl > 0
          delay = ()->
            @bot.speak "We have a superuser in the HOUSE! #{user.name}, welcome aboard the PARTY BUS!"

          setTimeout delay, 5000
        else
          @joinedUsers[user.name] = user
          
          delay = ()->
            users_text = (name for name in _.keys(@joinedUsers)).join(", ")
            
            @bot.speak "Hello #{users_text}, welcome aboard the PARTY BUS!"
            
            @joinedUsers = {}
            joinedTimeout = null

          if not joinedTimeout
            joinedTimeout = setTimeout delay, 15000
      
      for user in data.user
        # Double join won't spam
        @roomUsersLeft[user.userid] = new Date()
    
    @bot.on "update_user", (data) ->
      # Track name changes
      if data.name
        update_name(data.userid, data.name)
    
    @bot.on "deregistered", (data)->
      user = data.user[0]
      delete @active[user.userid]
      @roomUsersLeft[user.userid] = new Date()
    
    # Add and remove moderator
    @bot.on "new_moderator", (data) ->
      if data.success
        if data.userid is @userId
          @selfModerator = true
        else
          @mods[data.userid] = true
    
    @bot.on "rem_moderator", (data) ->
      if data.success
        if data.userid is @userId
          @selfModerator = false
        else
          delete @mods[data.userid]
    
    # Time if a dj rejoins, to resume their song count. Set to about three songs as default (20 minutes). Also gets reset by waiting, whichever comes first.
    DJ_REUP_TIME = 20 * 60 * 1000

    @bot.on "add_dj", (data)->
      user = data.user[0]
      update_name(user.name, user.userid)
      uid = user.userid
      update_idle(uid)
      
      if @boost
        if not (uid of @vips or uid of @allowed or is_mod(uid) or is_owner(uid)) and @selfModerator
          # Escort off stage
          escort(uid)
          
          @bot.speak "Hey #{user.name}, back of the bus for you! We're letting a VIP up on stage right now!"
        else if (uid of @vips or uid of @allowed)
          @boost = off
      else
        if room_mode is NORMAL_MODE
          if enabled and _.keys(@djSongCount).length >= @get_config('moderate_dj_min')
            if uid of djWaitCount and uid not of @vips and djWaitCount[uid] <= @get_config('wait_songs')
              waitSongs = @get_config('wait_songs') - djWaitCount[uid]
              @bot.speak "#{user.name}, party foul! Wait #{waitSongs} more song#{plural(waitSongs)} before getting on the decks again!"
              
              if @selfModerator
                # Escort off stage
                escort(uid)
        else if room_mode is VIP_MODE
          if not (uid of @vips or is_mod(uid) or is_owner(uid))
            if @selfModerator
              # Escort off stage
              escort(uid)
            @bot.speak "#{user.name}, it's VIPs only on deck right now!"
    #    else if room_mode is BATTLE_MODE
        
      # Resume song count if DJ rejoined too quickly
      if uid of @pastDjSongCount and now().getTime() - @pastDjSongCount[uid].when.getTime() < DJ_REUP_TIME
        @djSongCount[uid] = @pastDjSongCount[uid].count
      else
        @djSongCount[uid] = 0

    @bot.on "rem_dj", (data)->
      user = data.user[0]
      uid = user.userid
      
      @db.collection 'djs', (err, col)->
        criteria =
          'userInfo.userid': uid
        modifications =
          '$set':
            'userInfo': user
            'onstage': false
        col.update criteria, modifications, {upsert: true}
      
      # Add to timeout list if DJ has played 
      if enabled and @djSongCount[uid] >= @get_config('max_songs') and not djWaitCount[uid]
        # I believe the new song message is triggered first. Could ignore the message if it is too soon
        djWaitCount[uid] = 0
        
      # TODO consider lineskipping
      @pastDjSongCount[uid] = { count: @djSongCount[uid], when: new Date() }
      delete @djSongCount[uid]
      delete @campingDjs[uid]
      delete @warnedDjs[uid]
    
    track_action = (action, user, target) ->
      if not actions[action][user.userid]?
        actions[action][user.userid] =
          given: 1
          received: 0
      else
        actions[action][user.userid].given += 1
      
      @db.collection 'actions', (err, col)->
        criteria =
          'userInfo.userid': user.userid
          'action': action
        modifications =
          '$set':
            'userInfo': user
          '$inc':
            'given': 1
        col.update criteria, modifications, {upsert: true}
      
      if not actions[action][target.userid]?
        actions[action][target.userid] =
          given: 0
          received: 1
      else
        actions[action][target.userid].received += 1    
      
      @db.collection 'actions', (err, col)->
        criteria =
          'userInfo.userid': target.userid
          'action': action
        modifications =
          '$set':
            'userInfo': target
          '$inc':
            'received': 1
        col.update criteria, modifications, {upsert: true}
    
    @bot.on "snagged", (data) ->
      @track_action("hearts", @roomUsers[data.userid], @currentDj)
    
    rl = readline.createInterface(process.stdin, process.stdout)
        
    rl.on "line", (line) ->
      [cmd_txt, args] = command(line)

      user = @roomUsers[@selfId]
      
      matcher = cmd_matches(cmd_txt)
      out = (txt) -> util.puts txt
      
      if resolved_cmd = _.find(cli_commands, matcher)
        resolved_cmd.fn(user, args, out)
      else if resolved_cmd = _.find(@commands, matcher)
        resolved_cmd.fn(user, args, out)
    
    rl.on "close", ->
      process.stdout.write '\n'
      process.exit 0
    
    @bot.on "speak", (data) ->
      update_name(data.name, data.userid)
      update_idle(data.userid)
      [cmd_txt, args] = command(data.text)
      user = @roomUsers[data.userid]
      
      resolved_cmd = _.find(@commands, cmd_matches(cmd_txt))
      
      if resolved_cmd and allowed_cmd(user, resolved_cmd)
        if logged_cmd(resolved_cmd)
          util.puts "MOD #{now().toTimeString()}: #{data.name}: #{data.text}"
          @db.collection 'commands', (err, col)->
            col.insert
              user: user
              cmd: cmd_txt
              args: args
              when: new Date()
        resolved_cmd.fn(user, args, (txt) -> @bot.speak(txt))
      
      if @chat_enabled
        util.puts "#{data.name}: #{data.text}"
      
      @chat_action user, cmd_txt, args

      @db.collection 'chat', (err,col)->
        col.insert data

  chat_action: (user, cmd, arg) ->
    if cmd is "/me"
      [cmd, arg] = command(arg)
    
    # TODO
  
  # TODO, match regexes, and have a hidden, so commands automatically lists
  commands: [
    {cmd: "/allowed", fn: @cmd_allowed, help: "allowed djs"}
    {cmd: "/album", fn: @cmd_album, help: "current song album"}
    {cmd: "/ball", name: "/ball so hard", fn: @cmd_ballsohard, help: "ball so hard"}
    {cmd: "/commands", fn: @cmd_commands, hidden: true, help: "get list of commands"}
    {cmd: "/dance", fn: @cmd_dance, help: "dance!"}
    {cmd: "/daps", fn: @cmd_daps, help: "daps"}
    {cmd: "/djs", fn: @cmd_throttled_djs, help: "dj song count"}
    {cmd: "/hearts", fn: @cmd_hearts, help: "get hearts count"}
    {cmd: "/hugs", fn: @cmd_hugs, help: "get hugs count"}
    {cmd: ["/help", "/rules", "/?"], name: "/help", fn: @cmd_help, help: "get help"}
    {cmd: ["/last", "/prev", "/last_song", "/prev_song"], name: "/last", fn: @cmd_last_song, help: "votes for the last song"}
    {cmd: "/mods", fn: @cmd_mods, help: "lists room mods"}
    {cmd: "/party", fn: @cmd_party, help: "party!"}
    {cmd: "/power", fn: @cmd_power, help: "checks the power level of a user using the scouter"}
    {cmd: ["q", "/q", "/queue", "q?", "list"], name: "/queue", fn: @cmd_queue, hidden: true, help: "get dj queue info"}
    {cmd: "q+", fn: @cmd_queue_add, hidden: true, help: "add to dj queue"}
    {cmd: "/ragequit", fn: @cmd_ragequit, help: "ragequit"}
    {cmd: ["/timeout", "/wait", "/waiting", "/waitlist"], name: "/timeout", fn: @cmd_waiting, help: "dj timeout list"}
    {cmd: "/users", fn: @cmd_users, help: "counts room users"}
    {cmd: "/stagedive", fn: @cmd_stagedive, help: "stage dive!"}
    {cmd: "/vips", fn: @cmd_vips, help: "list vips in the bus"}
    # {cmd: "/vuthers", fn: @cmd_vuthers, help: "vuther clan roll call"}
    {cmd: "/d-_-bs", fn: @cmd_dbs, help: "d-_-b's roll call"}
    
    # Mod commands
    {cmd: "/allow", fn: @cmd_allow, owner: true, help: "allow a dj"}
    {cmd: "/unallow", fn: @cmd_unallow, owner: true, help: "unallow a dj"}
    {cmd: "/boost", fn: @cmd_boost, mod: true, help: "allow a dj up"}
    {cmd: "/chinesefiredrill", fn: @cmd_chinesefiredrill, owner: true, help: "boot everybody off stage. Must type THIS IS ONLY A DRILL :D"}
    {cmd: "/set", fn: @cmd_set, owner: true, help: "set bot configuration variables"}
    {cmd: "/get", fn: @cmd_get, mod: true, help: "get bot configuration variables"}
    {cmd: "/vip", fn: @cmd_vip, owner: true, help: "make user a vip (no limit)"}
    {cmd: "/unvip", fn: @cmd_unvip, owner: true, help: "remove vip status"}
    {cmd: "/setsongs", fn: @cmd_setsongs, owner: true, help: "set song count"}
    {cmd: "/reset", fn: @cmd_resetdj, owner: true, help: "reset song count for djs"}
    {cmd: "/escort", fn: @cmd_escort, mod: true, help: "escort a dj"}
    {cmd: "/boot", fn: @cmd_boot, mod: true, help: "boot a user"}
    {cmd: "/on", fn: @cmd_on, owner: true, help: "turn on dj limits"}
    {cmd: "/off", fn: @cmd_off, owner: true, help: "turn off dj limits"}
    {cmd: "/uid", fn: @cmd_uid, owner: true, help: "get user id"}
    {cmd: "/permaban", fn: @cmd_permaban, owner: true, help: "ban a user"}
    {cmd: "/unpermaban", fn: @cmd_unpermaban, owner: true, help: "unban a user"}
    {cmd: "/night", fn: @cmd_night, owner: true, help: "night mode"}
    {cmd: "/day", fn: @cmd_day, mod: true, help: "day mode"}
  ]

  allowed_cmd: (user, cmd) ->
    @is_owner(user.userid) or (not cmd.owner and (@is_mod(user.userid) or not cmd.mod))
  
  logged_cmd = (cmd) ->
    cmd.owner or cmd.mod
  
  cmd_matches = (txt) ->
    matches = (cmd) ->
      if typeof cmd is "string"
        if cmd is txt
          true
      else if "length" of cmd
        _.find(cmd, matches)
      else if typeof cmd is "function" and cmd.test(txt)
        true
    
    (entry) -> matches(entry.cmd)
  
  cmd_debug: (user, args) ->
    arg = norm(args)
    if arg is "true" or arg is "on"
      util.puts "Debug mode enabled!"
      debug_on = true
    else
      util.puts "Debug mode OFF"
      debug_on = false
  
  cmd_rename: (user, args, out) ->
    args = args.trim()
    
    if args isnt ""
      check = (data) ->
        if data.success
          out "Changed name to #{args}!"
        else
          out "Failed to change name: #{data.err}"
      
      @bot.modifyName(args, check)
    else
      out "You have to give a name!"
  
  cmd_chat: (user, args) ->
    @bot.speak args.trim()
  
  @cmd_whoami = (user, args, out) ->
    if options.userId of @roomUsers
      out "Logged in as #{@roomUsers[options.userId].name}"
    else
      out "Couldn't find myself"
  
  @cmd_togglechat = ->
    @chat_enabled = not @chat_enabled
    
  cli_commands: [
    {cmd: "/chat", fn: @cmd_chat, help: "make the bot say something"}
    {cmd: "/togglechat", fn: @cmd_togglechat, help: "view chat"}
    {cmd: "/debug", fn: @cmd_debug, help: "enable/disable debug"}
    {cmd: "/djs", fn: @cmd_djs, help: "dj song count"}
    {cmd: "/name", fn: @cmd_rename, help: "change bot name"}
    {cmd: "/whoami", fn: @cmd_whoami, help: "check who the bot is"}
  ]
  
  # Commands
  cmd_last_song: ->
    if @lastScore isnt ""
      @bot.speak "The previous song: #{@lastScore}"
    else
      @bot.speak "I blacked out and forgot what the last song was."
  
  cmd_album: ->
    @roomInfo (data) ->
      if @album isnt ""
        @bot.speak "Song album: #{@album}"
  
  cmd_boot: (user, args) ->
    if @selfModerator
      boot_pat = /^\s*(.*?)\s*:\s*([^\s].+?)\s*$/
      
      if match = boot_pat.exec(args)
        name = match[1]
        reason = match[2]
        
        if uid = @get_uid(name)
          if uid is options.userId
            @bot.speak "I'm not booting myself!"
          else
            @bot.bootUser(uid, reason)
        else
          @bot.speak "I couldn't find #{name} to boot!"
      else
        @bot.speak "#{user.name} you have to give a reason to boot!"
    else
      @bot.speak "I'm powerless, do it yourself!"
  
  cmd_escort: (user, args) ->
    if @@selfModerator
      if dj = @get_dj(args)
        @bot.remDj(dj)
    else
      @bot.speak "I'm powerless, do it yourself!"
  
  cmd_allow: (user, args, out) ->
    if target = @get_by_name(args)
      if target.userid not of @allowed
        @allowed[target.userid] = target
        @bot.speak "#{target.name}, get up on deck!"
        
        @db.collection 'users', (err, col)->
          criteria =
            'userInfo.userid': target.userid
          modifications =
            '$set':
              'userInfo': target
              'allowed': true
          col.update criteria, modifications, {upsert: true}
      else
        @bot.speak "#{target.name} is already allowed on deck"
    else
      out "I couldn't find #{args} to add to the allowed DJ list!"
  
  cmd_unallow: (user, args) ->
    dj = @get_by_name(args)
    
    if dj.userid of @allowed
      @bot.speak "#{dj.name} is no longer on the allowed DJ list"
      delete @allowed[dj.userid]
      @db.collection 'users', (err, col)->
        criteria =
          'userInfo.userid': dj.userid
        modifications =
          '$set':
            'userInfo': dj
            'allowed': false
        col.update criteria, modifications, {upsert: true}
    else
      @bot.speak "#{args} is not on the allowed DJ list!"
  
  cmd_allowed: (user, args, out) ->
    args = norm(args)
    
    users = _.filter(@allowed, (user) -> user.userid not of @vips)
    
    if args is "all"
      msg = ""
      
      if users.length > 0
        allowed_list = (user.name for user in users).join(", ")
        msg += "All allowed DJs: #{allowed_list}"
      else if _.keys(@vips).length == 0
        msg += out "There is no one on the allowed DJs list!"
      
      if _.keys(@vips).length > 0
        vip_list = (vipUser.name for vipId, vipUser of @vips).join(", ")
        msg += " VIPs: #{vip_list}"
      
      out msg
    else
      present_users = _.filter(users, (user) -> user.userid of @active)
      present_vips = _.filter(@vips, (user) -> user.userid of @active)
      
      msg = ""
      
      if present_users.length > 0
        allowed_list = (user.name for user in present_users).join(", ")
        msg += "Allowed DJs: #{allowed_list}"
      else if present_vips.length == 0
        msg += "There are no allowed DJs in the Party Bus right now"
  
      if present_vips.length > 0
        vip_list = (vipUser.name for vipUser in present_vips).join(", ")
        msg += " VIPs: #{vip_list}"
      
      out msg
  
  cmd_vip: (user, args, out) ->
    if vipUser = @get_by_name(args)
      if vipUser.userid not in _.keys @vips
        @vips[vipUser.userid] = vipUser
        @bot.speak "Party all you want, #{vipUser.name}, because you're now a VIP!"

        @db.collection 'users', (err, col)->
          criteria =
            'userInfo.userid': vipUser.userid
          modifications =
            '$set':
              'userInfo': vipUser
              'vip': true
          col.update criteria, modifications, {upsert: true}
      else
        @bot.speak "#{vipUser.name} is already a VIP on the Party Bus!"
    else
      out "I couldn't find #{args} in the bus to make a VIP!"
  
  cmd_unvip: (user, args) ->
    vipUser = @get_by_name(args)
    
    if vipUser.userid of @vips
      @bot.speak "#{vipUser.name} is no longer special"
      delete @vips[vipUser.userid]

      @db.collection 'users', (err, col)->
        criteria =
          'userInfo.userid': vipUser.userid
        modifications =
          '$set':
            'userInfo': vipUser
            'vip': false
        col.update criteria, modifications, {upsert: true}
    else
      @bot.speak "#{args} is not a VIP in the Party Bus!"
  
  cmd_vips: (user, args, out) ->
    args = norm(args)
    if args is "all"
      if _.keys(@vips).length > 0
        vip_list = (vipUser.name for vipId, vipUser of @vips).join(", ")
        out "All VIPs in the Party Bus: #{vip_list}"
      else
        out "There are no VIPs in the Party Bus right now"
    else
      present_vips = _.filter(@vips, (user) -> user.userid of @active)
      
      if present_vips.length > 0
        vip_list = (user.name for user in present_vips).join(", ")
        out "Current VIPs in the Party Bus are #{vip_list}"
      else
        out "There are no VIPs in the Party Bus right now"
  
  cmd_party: (user, args) ->
    if norm(args) is "on wayne"
      @bot.speak "Party on Garth!"
    else
      @bot.speak "AWWWWWW YEAHHHHHHH!"
    
    @bot.vote "up"
  
  dances: [
    "Erryday I'm Shufflin'"
    "/me dances"
    "Teach me how to dougie!"
    "/me dougies"
    ]
  
  cmd_ballsohard: (user, args) ->
    if norm(args) is "so hard"
      @bot.speak "Muhfuckas wanna fine me!"
      @bot.vote "up"
  
  cmd_dance = -> 
    @bot.speak random_select(@dances)
    @bot.vote "up"

  cmd_daps: (user) ->
    name = user.name
    
    if name is "marinating minds"
      name = "SAUCEY"
    
    @bot.speak "DAPS #{name}"
  
  djs_last = null
  DJS_THROTTLE = 30 * 1000
  
  cmd_throttled_djs = (user, args, out) ->
    if not djs_last or (new Date()).getTime() - djs_last.getTime() > DJS_THROTTLE
      if _.keys(@djSongCount).length == 0
        out "I don't have enough info yet for a song count"
      else
        txt = "Song Totals: "
        djs_last = new Date()
        roomInfo (data) ->
          newDjSongCount = {}
          
          for dj in data.room.metadata.djs
            newDjSongCount[dj] = @djSongCount[dj] or 0
          
          @djSongCount = newDjSongCount
          
          out (txt + ("#{@roomUsers[dj].name}: #{count}" for dj, count of @djSongCount).join(", "))
  
  cmd_djs = (user, args, out) ->
    if _.keys(@djSongCount).length == 0
      out "I don't have enough info yet for a song count"
    else
      txt = "Song Totals: "
      roomInfo (data) ->
        newDjSongCount = {}
        
        for dj in data.room.metadata.djs
          newDjSongCount[dj] = @djSongCount[dj] or 0
        
        @djSongCount = newDjSongCount
        
        out (txt + ("#{@roomUsers[dj].name}: #{count}" for dj, count of @djSongCount).join(", "))

  cmd_mods = ->
    roomInfo (data) ->
      # Collect mods
      mod_list = (@roomUsers[modId].name for modId in data.room.metadata.moderator_id when @active[modId] and modId isnt @userId and modId not in options.excluded_mods).join(", ")
      @bot.speak "Current mods in the Party Bus are #{mod_list}"
  
  cmd_users = ->
    roomInfo (data) ->
      count = _.keys(data.users).length
      @bot.speak "There are #{count} peeps rocking the Party Bus right now!"
  
  cmd_help = (user, args) ->
    if room_mode is VIP_MODE
      @bot.speak "Hey #{user.name}, welcome aboard the party bus. Read the room rules: #{@get_config('rules_link')}. It's VIPs (and mods) only on deck right now!"
    else if room_mode is BATTLE_MODE
      @bot.speak "Hey #{user.name}, welcome aboard the party bus. Read the room rules: #{@get_config('rules_link')}! It's a King of the Hill battle right now!"
    else if room_mode is NORMAL_MODE
      @bot.speak "Hey #{user.name}, welcome aboard the party bus. Read the room rules: #{@get_config('rules_link')}"
  
  cmd_hidden = (cmd) ->
    cmd.hidden or cmd.owner or cmd.mod
  
  cmd_commands = ->
    cmds = _.select(@commands, (cmd) -> not cmd_hidden(cmd))
    cmds_text = _.map(cmds, (entry) -> entry.name or entry.cmd).join(", ")
    
    @bot.speak cmds_text
  
  cmd_waiting = ->
    if _.keys(djWaitCount).length == 0
      @bot.speak "No DJs are in the naughty corner!"
    else
      waiting_list = ("#{@roomUsers[dj].name}: #{@get_config('wait_songs') - count}" for dj, count of djWaitCount).join(", ") + " songs"
      @bot.speak "DJ naughty corner: #{waiting_list}"
  
  cmd_queue = (user, args) ->
    if room_mode is VIP_MODE
      @bot.speak "#{user.name}, the Party Bus has no queue! It's VIPs (and mods) only on deck right now!"
    else if room_mode is BATTLE_MODE
      @bot.speak "#{user.name}, the Party Bus has no queue! It's a King of the Hill battle right now!"
    else if room_mode is NORMAL_MODE
      if not queueEnabled
        @bot.speak "#{user.name}, the Party Bus has no queue! It's FFA, #{@get_config('max_songs')} song limit, #{@get_config('wait_songs')} song wait time"
  
  cmd_queue_add = (user, args) ->
    if room_mode is VIP_MODE
      @bot.speak "#{user.name}, the Party Bus has no queue! It's VIPs (and mods) only on deck right now!"
    else if room_mode is BATTLE_MODE
      @bot.speak "#{user.name}, the Party Bus has no queue! It's a King of the Hill battle right now!"
    else if room_mode is NORMAL_MODE
      if not queueEnabled
        @bot.speak "#{user.name}, the Party Bus has no queue! It's FFA, #{@get_config('max_songs')} song limit, #{@get_config('wait_songs')} song wait time"
  
  cmd_ragequit = (user) ->
    @bot.speak "Lol umadbro?"
    @bot.bootUser(user.userid, "gtfo")
  
  cmd_vuthers = ->
    roomInfo (data) ->
      vuther_pat = /\bv[aeiou]+\w*th[aeiou]\w*r/i
      
      daddy = false
      
      is_vutherbot = (name) ->
        if name is "vuther"
          daddy = true
          return false
        else
          return vuther_pat.test(name)
      
      vuthers = _.select(data.users, (user) -> is_vutherbot(user.name))
      vuthers = _.map(vuthers, (user) -> user.name)
      
      msg = "vuther force, assemble!"
      
      if vuthers.length > 0
        msg += " There are #{vuthers.length} vuthers here: " + vuthers.join(", ") + "."
      else
        msg += " There are no vuthers here..."
      
      if daddy
        if vuthers.length > 0
          msg += " And daddy vuther is here!"
        else
          msg += " But daddy vuther is here!"
      
      @bot.speak msg
  
  cmd_dbs = ->
    roomInfo (data) ->
      db_pat =  /.*d.*?_.*?b.*/i
      
      daddy = false
      
      is_db = (name) ->
        if name is "d-_-b"
          daddy = true
          return false
        else
          return db_pat.test(name)
      
      dbs = _.select(data.users, (user) -> is_db(user.name))
      dbs = _.map(dbs, (user) -> user.name)
      
      msg = "d-_-b team, ASSEMBLEEEE!"
      
      if dbs.length > 0
        msg += " There are #{dbs.length} soldiers in the d-_-b army here: " + dbs.join(", ") + "."
      else
        msg += " There are no d-_-bs here..."
      
      if daddy
        if dbs.length > 0
          msg += " And d-_-b is here!"
        else
          msg += " But d-_-b is here!"
      
      @bot.speak msg
  
  cmd_setsongs = (user, args) ->
    setsongs_pat = /^(.+?)\s+(-?\d+)\s*$/
    
    if match = setsongs_pat.exec(args)
      name = match[1]
      count = parseInt(match[2])
      
      if dj = get_dj(name)
        @djSongCount[dj] = count
        
        # Set camping if over
        if count >= @get_config('max_songs') and dj not of @campingDjs
          @campingDjs[dj] = 0
        
        # Remove camping if under
        if count < @get_config('max_songs') and dj of @campingDjs
          delete @campingDjs[dj]
  
  cmd_resetdj = (user, args) ->
    if djUser = get_by_name(args)
      if djUser.userid of @djSongCount
        @djSongCount[djUser.userid] = 0
      
      delete @campingDjs[djUser.userid]
      delete djWaitCount[djUser.userid] 
  
  cmd_off = ->
    enabled = false
    @bot.speak "Party all you want, because DJ limits are off!"
  
  cmd_on = ->
    enabled = true
    @bot.speak "DJ limits are enabled again"
  
  cmd_uid = (user, args, out) ->
    if user = get_by_name(args)
      out user.userid
  
  cmd_permaban = (user, args) ->
    boot_pat = /^\s*(.*?)\s*:\s*([^\s].+?)\s*$/
    
    if match = boot_pat.exec(args)
      uid = undefined
      name = match[1]
      reason = match[2]
    
      if is_uid(name)
        uid = name
      else if user = get_by_name(name)
        uid = user.userid
        
      if uid
        if uid is options.userId
          @bot.speak "I'm not booting myself!"
        else
          if @selfModerator
            @bot.bootUser(uid, reason)
            @bot.speak "Banning #{name}"
          else
            @bot.speak "I'm powerless to ban anyone, but #{name} is on the list!"
                  
          @permabanned[uid] = reason
    else
      @bot.speak "#{user.name} you have to give a reason to ban someone!"
  
  cmd_unpermaban = (user, args) ->
    name = args.toLowerCase()
    
    if name of @permabanned
      delete @permabanned[name]
      @bot.speak "Unbanning #{@roomUsers[name].name}"
    else if user = get_by_name(name)
      delete @permabanned[user.userid]
      @bot.speak "Unbanning #{@roomUsers[user.userid].name}"
  
  cmd_chinesefiredrill = (user, args) ->
    roomInfo (data) ->
      if @selfModerator and args is "THIS IS ONLY A DRILL"
        @bot.speak "CHINESE FIRE DRILL! In 3"
        
        callback = ->
          for uid in data.room.metadata.djs
            @bot.remDj(uid)
          @bot.bootUser(user.userid, "for pulling the fire alarm")
        
        it = (i) -> @bot.speak(i)
        delay_countdown(callback, it, 2)
      else
        @bot.speak "CHINESE FIRE DRILL DRILL! In 3"
        
        msg = -> @bot.speak "Escorting " + (@roomUsers[dj].name for dj in data.room.metadata.djs).join(", ") + " and booting #{user.name} for pulling the fire alarm."
        it = (i) -> @bot.speak(i)
        delay_countdown(msg, it, 2)
        
  
  cmd_power = (user, args) ->
    roomInfo (data) ->
      name = norm(args)
      
      if name isnt ""
        # Initialize users
        if user = _.find(data.users, (user) -> norm(user.name) is norm(args))
          power = Math.floor(user.points / 1000)
          if power > 0
            @bot.speak "Vegeta, what does the scouter say about #{user.name}'s power level? It's over #{power}000!!!"
          else
            @bot.speak "#{user.name} doesn't have much of a power level..."
        else
          @bot.speak "The scouter couldn't find anyone named #{args}!"
      else
        @bot.speak "Who?"
  
  cmd_night = ->
    @set_config('wait_songs', @get_config('wait_songs_night'))
    
    @bot.speak "It's late at night! DJs wait #{@get_config('wait_songs')} songs"
    
    for dj, count of djWaitCount
      if count > @get_config('wait_songs')
        delete djWaitCount[dj]
  
  cmd_day = ->
    @set_config('wait_songs', @get_config('wait_songs_day'))
    
    @bot.speak "It's bumping in here! DJs wait #{@get_config('wait_songs')} songs"
  
  cmd_stagedive = (user) ->
    if user.userid of @djSongCount
      @bot.remDj(user.userid)
      @bot.speak "#{user.name}, go crowd surfing!"
      
  cmd_boost = (user, args) ->
    if norm(args) is "off"
      @boost = off
      
      @bot.speak "No more rocket boost!"
    else
      @boost = on
      
      @bot.speak "VIPs and allowed DJs, get up on deck!"
  
  command = (line) ->
    cmd_pat = /^([^\s]+?)(\s+([^\s]+.+?))?\s*$/
    
    cmd = ""
    args = ""
    
    if match = cmd_pat.exec(line)
      cmd = match[1].toLowerCase()
      args = match[3] or ""
    
    [cmd, args]
  
  cmd_set = (user, args, out) ->
    [x, value] = command(args)
    
    @set_config(x, value)
  
  cmd_get = (user, args, out) ->
    [x] = command(args)
    
    if x? and x of config_props
      props = config_props[x]
    
      result = config[x] ? props.default
      
      result = if props.format? and (pretty = config_format[props.format]?.pretty)? then pretty(result, props.unit) else result
      
      out "#{props.name}: #{result}"
  
  cmd_hearts = (user, args) ->
    if args is "given"
    else if args is "top"
    else
      count = actions["hearts"][user.userid]?.received ? 0
      
      if count == 0
        @bot.speak = "You are a heartless bastard"
      else
        @bot.speak = "You have #{count} heart#{plural(count)}"

exports.busDriver = BusDriver

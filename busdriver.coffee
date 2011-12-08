Bot = require 'ttapi'
irc = require 'irc'
_ = require 'underscore'
util = require 'util'
readline = require 'readline'
mongodb = require('mongodb')

greet = require './greetings'

###
Constants
###
SECOND = 1000
MINUTE = 60*SECOND
HOUR = 60 * MINUTE
DAY = 24 * HOUR
WEEK = 7 * DAY
MONTH = 30 * DAY
YEAR = 365.25 * DAY

class BusDriver
  ###
  Bus specific constants
  ###
  NORMAL_MODE = 0
  VIP_MODE = 1
  BATTLE_MODE = 2
  
  ###
  General utility functions
  ###
  is_number = (num) -> num? and not isNaN(num)
  
  plural = (count) =>
    if count isnt 1
      's'
    else
      ''

  now = => new Date()

  elapsed = (date) =>
    if date
      new Date().getTime() - date.getTime()
    else
      -1

  random_select = (list) =>
    list[Math.floor(Math.random()*list.length)]

  countdown = (callback, it, time) =>
    if time > 0
      it(time)
      delay = => countdown(callback, it, time-1)
      setTimeout(delay, 1000)
    else
      callback()

  delay_countdown = (callback, it, time) =>
    delay = => countdown(callback, it, time)
    
    setTimeout(delay, 1000)

  norm = (text) =>
    text.trim().toLowerCase()

  is_uid = (uid) =>
    uid and uid.length == 24

  command = (line) =>
    cmd_pat = /^([^\s]+?)(\s+([^\s]+.*?))?\s*$/
    
    cmd = ""
    args = ""
    
    if match = cmd_pat.exec(line)
      cmd = match[1].toLowerCase()
      args = match[3] or ""
    
    [cmd, args]

  ###
  State dependent utility functions
  ###
  is_vip: (uid) =>
    uid of @vips
  
  is_allowed: (uid) =>
    uid of @allowed
      
  update_name: (name, uid) =>
    @roomUsernames[norm(name)] = uid
    
    if uid of @roomUsers
      @roomUsers[uid].name = name
  
  update_idle: (uid) =>
    @lastActivity[uid] = now()
    if uid of @warnedDjs
      delete @warnedDjs[uid]
  
  update_user: (user) =>
    @update_name(user.name, user.userid)
    @roomUsers[user.userid] = user
    
    @db_col 'users', (col) =>
      criteria =
        'userInfo.userid': user.userid
      modifications =
        '$set':
          'userInfo': user
      col.update criteria, modifications, {upsert: true}
  
  register: (user) =>
    @update_user(user)
    @active[user.userid] = true
    @update_idle(user.userid)
  
  get_by_name: (name) =>
    name = norm(name)
    if name of @roomUsernames
      @roomUsers[@roomUsernames[name]]
  
  get_uid: (name) =>
    @roomUsernames[norm(name)]

  get_dj: (name) =>
    uid = @get_uid(name)
    if uid of @djSongCount
      return uid
  
  uid_is_dj: (uid) =>
    uid of @djSongCount
      
  is_mod: (uid) =>
    uid of @mods
  
  is_owner: (uid) =>
    _.include(@owners, uid)

  escort_warn: (uid) =>
    @bot.remDj(uid)
    
    if uid not of @escortWarnings or elapsed(@escortWarnings[uid].when) > @get_config('escort_interval') * SECOND
      @escortWarnings[uid] =
        count: 1
        when: now()
    else
      @escortWarnings[uid].count += 1
      @escortWarnings[uid].when = now()
      
      if @escortWarnings[uid].count > @get_config('escort_limit')
        @bot.bootUser(uid, "Follow the rules! Wait for your turn on stage")
  
  ensure_escort: (uid) =>
    @escort_warn(uid)
    
    delay = =>
      @roomInfo (data) =>
        if uid in data.room.metadata.djs
          @escort_warn(uid)
    
    setTimeout delay, 500
  
  capacity_boot: =>
    if @userCount > @get_config('room_capacity')
      @roomInfo (data) =>
        num_boot = @userCount - @get_config('room_capacity')

        idlers = _.filter(_.keys(@active), (uid) => uid of @lastActivity and elapsed(@lastActivity[uid]) > @get_config('capacity_min_idle')*MINUTE and not @uid_is_dj(uid) and not @is_mod(uid) and not @is_owner(uid) and uid isnt @userId and not @is_vip(uid))
        top_idlers = _.last(_.sortBy(idlers, (uid) => elapsed(@lastActivity[uid])), num_boot)
        
        if @get_config('fake_idle_boot')
          if top_idlers.length > 0
            util.puts "Idle booting: " + [@roomUsers[uid].name for uid in top_idlers].join(", ")
        else
          for uid in top_idlers
            @bot.bootUser(uid, "Vote or chat to stay in the room!")
  
  ###
  Configuration
  ###
  to_ranged_int = (options) =>
    to_range = (arg) =>
      result = parseInt(arg)
      
      if not isNaN(result) and (not options.min? or result >= options.min) and (not options.max? or result <= options.max)
        return result
    
    to_range
  
  to_positive_int = (arg) =>
    result = parseInt(arg)
    
    if not isNaN(result) and result > 0
      result

  pretty_int = (value, unit) =>
    if unit?
      "#{value} #{unit}#{plural(value)}"
    else
      "#{value}"

  to_bool = (arg) =>
    arg = norm(arg)
    
    arg = arg is "true" or arg is "on" or arg is "yes"
  
  to_time = (arg, _unit = "s") =>
    time_pat = /^\s*(\d+|\d+\.\d*|\d*\.\d+)\s*([^\s]+)?\s*$/
    
    if match = time_pat.exec(line)
      number = parseFloat(match[1])
      unit = match[2]
      
      if not unit? or _unit is ""
        unit = _unit
      
      if unit.indexOf("s") is 0
        number * SECOND
      else if unit.indexOf("ms") is 0 or unit.indexOf("mil") is 0
        number
      else if unit.indexOf("h") is 0
        number * HOUR
      else if unit.indexOf("d") is 0
        number * DAY
      else if unit.indexOf("w") is 0
        number * WEEK
      else if unit.indexOf("mo") is 0
        number * MONTH
      else if unit.indexOf("y") is 0
        number * YEAR
      else if unit.indexOf("m") is 0
        number * MINUTE
  
  time_units = [
    {name: "year", size: YEAR}
    {name: "month", size: MONTH}
    {name: "week", size: WEEK}
    {name: "day", size: DAY}
    {name: "hour", size: HOUR}
    {name: "minute", size: MINUTE}
    {name: "second", size: SECOND}
  ]
  
  to_pretty_time = (time) =>
    unit = _.first(_.range(0, time_units.length), (i) -> arg > time_units[i].size)
    
    if unit?
      first = Math.floor(time / time_units[unit].size)
      str = "#{first} #{time_units[unit].name}#{plural(first)}"
      
      if unit < time_units.length - 1
        second = Math.floor(time / time_units[unit + 1].size)
        
        if second > 0
          str += " "#{second} #{time_units[unit + 1].name}#{plural(second)}""
      
      str
    else
      num = time / 1000
      
      "{num} second#{plural(num)}"
  
  to_room_mode: (arg) =>
    arg = norm(arg)
    
    if arg is "vips" or arg is "vip"
      @bot.speak "It's a VIP party in here! VIPs (and mods) only on deck!"
      VIP_MODE
    else if arg is "battle"
      @bot.speak "Ready to BATTLE?!!!"
      BATTLE_MODE
    else
      @bot.speak "Back to the ho-hum. FFA, #{@get_config('max_songs')} song limit, #{@get_config('wait_songs')} wait time between sets"
      NORMAL_MODE
  
  pretty_room_mode: (value) =>
    if value is VIP_MODE
      "It's a VIP party in here! VIPs (and mods) only on deck!"
    else if value is BATTLE_MODE
      "Ready to BATTLE?!!!"
    else
      "The ho-hum. FFA, #{@get_config('max_songs')} song limit, #{@get_config('wait_songs')} wait time between sets"
  
  get_config: (key) =>
    if key of @config_props
      props = @config_props[key]
    
      result = if props.get? then props.get(key) else @config[key]
      
      result ? props.default
  
  set_config: (key, value, raw = false) =>
    @debug "Setting config #{key}:#{value}"
    if key of @config_props
      @debug "Config key #{key} exists"
      props = @config_props[key]
      
      if not raw and props.format?
        if to = @config_format[props.format]?.to
          value = to(value)
      
      value = value ? props.default
      
      if props.set?
        props.set(value)
      else
        @config[key] = value
      
      @db_col 'rooms', (col) =>
        criteria =
          roomId: @roomId
        modifications = 
          "$set": {}
        
        modifications["$set"]["config.#{key}"] = value
        
        col.update criteria, modifications, {upsert: true}
  
  debug: (txt) =>
    if @debug_on
      util.puts txt
  
  process_votelog: (votelog) =>
    # This might work... not sure what the votelog is
    for [uid, vote] in votelog
      if uid isnt ""
        @update_idle(uid)
  
  roomInfo: (callback) =>
    @bot.roomInfo (data) =>
      @userCount = _.keys(data.users).length
      @currentDj = if data.room.metadata.current_dj? then @roomUsers[data.room.metadata.current_dj]
    
      # Initialize song
      if data.room.metadata.current_song
        @songName = data.room.metadata.current_song.metadata.song
        @album = data.room.metadata.current_song.metadata.album
        @upVotes = data.room.metadata.upvotes
        @downVotes = data.room.metadata.downvotes
    
      @process_votelog data.room.metadata.votelog
      
      callback data
  
  ###
  Database
  ###
  db_col: (name, fn, queue = true) =>
    if name of @collections
      if @collections[name].ready
        @db.collection name, (err, col) =>
          if err
            util.puts "DB collection #{name} error: #{err}"
          else
            fn(col)
      else if queue
        # Add to queue
        @collections[name].queue.push(fn)
  
  ###
  Database initializers
  ###
  
  db_init_actions: (col) =>
    col.find {}, (err,cursor) =>
      cursor.each (err,doc) =>
        if doc isnt null
          if doc.action of @actions
            @actions[doc.action][doc.userInfo.userid] =
              given: if is_number(doc.given) then doc.given else 0
              received: if is_number(doc.received) then doc.received else 0
  
  db_init_config: (col) =>
    criteria =
      "roomId": @roomId
    
    col.findOne criteria, (err,doc) =>
      if doc?
        for key, value of doc.config
          @set_config(key, value, true)
  
  db_init_djs: (col) =>
    col.find {}, (err,cursor) =>
      cursor.each (err,doc) =>
        if doc isnt null
          if doc.active
            @djSongCount[doc.userInfo.userid] = doc.count
          
          if doc.camping?
            @campingDjs[doc.userInfo.userid] = doc.camping
  
  db_init_users: (col) =>
    col.find {}, (err,cursor) =>
      cursor.each (err,doc) =>
        if doc isnt null
          if doc.vip
            @vips[doc.userInfo.userid] = doc.userInfo
          
          if doc.allowed
            @allowed[doc.userInfo.userid] = doc.userInfo
          
          if doc.userInfo.userid not of @roomUsers
            @update_user(doc.userInfo)
  
  ###
  Constructor
  ###
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

    # Initialize bot
    @bot = new Bot options.userAuth, options.userId, options.roomId
    
    ###
    Variables
    ###
    
    ###
    Song Info
    ###
    @songName = ""
    @album = ""
    @upVotes = 0
    @downVotes = 0
    @lastScore = ""
    
    ###
    Room users
    ###
    @roomUsers = {}
    @roomUsernames = {}
    @active = {}
    @roomUsersLeft = {}
    @userCount = 1
    
    @lastActivity = {}
    
    ###
    Special users
    ###
    @owners = options.owners
    @excluded_mods = options.excluded_mods or []
    @mods = {}
    @vips = {}
    @allowed = {}
    
    # Greetings
    @joinedUsers = {}
    @greetingTimeout = null
    
    @permabanned = {}
    
    ###
    DJ Tracking
    ###
    @djs = {}
    @djSongCount = {}
    @campingDjs = {}
    
    # Count songs DJs have waited for
    @djWaitCount = {}
    
    @currentDj = undefined
    @lastDj = undefined
    @warnedDjs = {}
    @queueEnabled = false
    
    @escortWarnings = {}
    @limits_enabled = true
    @boost = false
    
    ###
    Actions
    ###
    @tracked_actions = [
      "hearts"
      "hugs"
    ]
    
    @actions = {}
    
    for action in @tracked_actions
      @actions[action] = {}
    
    ###
    Bot info
    ###
    @selfModerator = false
    @chat_enabled = false
    @pastDjSongCount = {}
    
    ###
    Database
    ###
    @db_ready = false
    @db_queue = {}
    @collections =
      actions:
        init: @db_init_actions
      'chat':
        foo: "hello"
      'commands':
        foo: "hello"
      'djs':
        init: @db_init_djs
      'rooms':
        init: @db_init_config
      'users':
        init: @db_init_users
      'login':
        foo: "hello"
    
    for name, props of @collections
      props.queue = []
    
    db_connection = new mongodb.Db 'TheBusDriver', (new mongodb.Server '127.0.0.1', 27017, {})
    db_connection.open (err, db) =>
      if err
        @debug "DB connection error: #{err}"
      else
        @db = db
        @db_ready = true
        @debug "DB Connection Ready"
        
        for name, props of @collections
          @db.collection name, (err, col) =>
            if err
              @debug "DB collection #{name} error: #{err}"
            else
              @debug "DB collection #{name}"
            
              # Run initializer
              if props.init?
                @debug "Running initializer for collection #{name}"
                props.init(col)
              
              # Run queued up actions
              for action in props.queue
                action(col)
              
              # Clear out queue
              props.queue = []
              
              @debug "DB Collection #{name} ready!"
              props.ready = true

    options.ircHandle = options.ircHandle or "BusDriver"
    
    @room_mode = NORMAL_MODE
    @debug_on = false
    
    ###
    Config
    ###
    @config = {}

    @config_props =    
      max_songs: {default: 3, unit: "song", format: "+int", name: "Song limit"}
      camp_songs: {default: 2, unit: "song", format: "+int", name: "DJ autoescort songs"} # How much tolerance we have before we just escort
      wait_songs: {default: 3, unit: "song", format: "+int", name: "DJ naughty corner songs"}
      wait_songs_day: {default: 3, unit: "song", format: "+int", name: "DJ naughty corner songs for day time"}
      wait_songs_night: {default: 1, unit: "song", format: "+int", name: "DJ naughty corner songs for night time"}
      wait_time: {default: 15, unit: "minute", format: "+int", name: "DJ naughty corner time"}
      greeting_delay: {default: 15, unit: "second", format: "+int", name: "User greeting delay"}
      special_greeting_delay: {default: 5, unit: "second", format: "+int", name: "Special greeting delay"}
      rejoin_greeting_interval: {default: 10, unit: "second", format: "+int", name: "Rejoin no greeting interval"} # Time to wait before considering a rejoining user to have actually come back rather than disconnect
      moderate_dj_min: {default: 3, unit: "dj", format: "+int", name: "Enforced rules DJ minimum"} # Minimum number of DJs to activate reup modding
      dj_warn_time: {default: 11, unit: "minute", format: "+int", name: "AFK DJ warning time"}
      dj_escort_time: {default: 15, unit: "minute", format: "+int", name: "AFK DJ escort time"}
      escort_interval: {default: 20, unit: "second", format: "+int", name: "Window to boot if escorted too many times"}
      escort_limit: {default: 3, unit: "time", format: "+int", name: "Too many escorts limit"}
      cmd_djs_throttle_time: {default: 30, unit: "second", format: "+int", name: "/djs command throttle time"}
      djs_resume_count_interval: {default: 20, unit: "minutes", format: "+int", name: "interval to resume song count"}
      mode: {default: NORMAL_MODE, format: "room_mode", name: "Room mode", set: ((value) => @room_mode = value), get: => @room_mode}
      debug: {default: off, format: "onoff", name: "Command line debug", set: ((value) => debug_on = value), get: => debug_on}
      rules_link: {default: "http://bit.ly/thepartybus", name: "Rules link"}
      greetings: {default: true, format: "onoff", name: "Greetings"}
      greetings_max_capacity: {default: 100, unit: "user", format: "+int", name: "Number of users to disable greetings at"}
      capacity_boot: {default: true, format: "onoff", name: "Boot at capacity"}
      fake_idle_boot: {default: false, format: "onoff", name: "Fake boot at capacity"}
      room_capacity: {default: 199, format: "room_cap", unit: "user", name: "Number to limit capacity to"}
      capacity_min_idle: {default: 10, format: "+int", unit: "minute", name: "Minimum idle time to capacity boot"}
      chat_spam: {default: true, format: "onoff", name: "Turn on/off all chat spam commands"}
      
      
    @config_format =
      "+int": {to: to_positive_int, pretty: pretty_int}
      "room_cap": {to: to_ranged_int({min: 195, max: 200}), pretty: pretty_int}
      "onoff": {to: to_bool, pretty: (value) => if value then "on" else "off"}
      "room_mode": {to: @to_room_mode, pretty: @pretty_room_mode}
            
    #ircClient = new irc.Client options.ircServer, options.ircHandle, 
    #  channels: [options.ircChan]
    
    #ircClient.addListener "message", (from, to, message) =>s
      # irc handling
      # no custom commands yet
    
    @bot.on "update_votes", (data) =>
      @upVotes = data.room.metadata.upvotes
      @downVotes = data.room.metadata.downvotes

      if @songName is ""
        @roomInfo (data) =>
          @songName = data.room.metadata.current_song.metadata.song
      
      # This might work... not sure what the votelog is
      @process_votelog data.room.metadata.votelog

    @bot.on "newsong", (data) =>
      if @songName isnt ""
          @bot.speak "#{@songName} - [#{@upVotes}] Awesomes, [#{@downVotes}] Lames"
          @lastScore = "#{@songName} - [#{@upVotes}] Awesomes, [#{@downVotes}] Lames"
      
      # Reset vote count
      @upVotes = data.room.metadata.upvotes
      @downVotes = data.room.metadata.downvotes
      
      @songName = data.room.metadata.current_song.metadata.song
      @currentDj = @roomUsers[data.room.metadata.current_dj]

      if @uid_is_dj(@currentDj.userid)
        @djSongCount[@currentDj.userid]++
      else
        @djSongCount[@currentDj.userid] = 1
      
      @db_col 'djs', (col) =>
        criteria =
          'userInfo.userid': @currentDj.userid
        modifications =
          '$set':
            'userInfo': @currentDj
            'onstage': true
            'songs': @djSongCount[@currentDj.userid]
        col.update criteria, modifications, {upsert: true}

      if @room_mode is NORMAL_MODE
        # Only mod if there are some minimum amount of DJs
        if @limits_enabled and _.keys(@djSongCount).length >= @get_config('moderate_dj_min')
          escorted = {}
          
          # Escort DJs that haven't gotten off!
          for dj in _.keys(@campingDjs)
            @campingDjs[dj]++
            
            if dj not of @vips and @selfModerator and @campingDjs[dj] >= @get_config('camp_songs')
              # Escort off stage
              @ensure_escort(dj)
              escorted[dj] = true
          
          if @lastDj? and @lastDj.userid not of escorted and @lastDj.userid not of @vips and @djSongCount[@lastDj.userid] >= @get_config('max_songs')
            @bot.speak "#{@lastDj.name}, you've played #{@djSongCount[@lastDj.userid]} songs already! Let somebody else get on the decks!"
            
            if @lastDj.userid not of @campingDjs
              @campingDjs[@lastDj.userid] = 0
        
        for dj in _.keys(@djWaitCount)
          @djWaitCount[dj]++
          
          # Remove from timeout list if the DJ has waited long enough
          if @djWaitCount[dj] >= @get_config('wait_songs')
            delete @djWaitCount[dj]
            delete @pastDjSongCount[dj]
      # else if @room_mode is BATTLE_MODE
      
      # Save DJ
      @lastDj = @currentDj

    @bot.on "add_dj", (data) =>
      user = data.user[0]
      @update_name(user.name, user.userid)
      uid = user.userid
      @update_idle(uid)
      
      if @boost
        if not (uid of @vips or uid of @allowed or @is_mod(uid) or @is_owner(uid)) and @selfModerator
          # Escort off stage
          @ensure_escort(uid)
          
          @bot.speak "Hey #{user.name}, back of the bus for you! We're letting a VIP up on stage right now!"
        else if (uid of @vips or uid of @allowed)
          @boost = off
      else
        if @room_mode is NORMAL_MODE
          if @limits_enabled and _.keys(@djSongCount).length >= @get_config('moderate_dj_min')
            if uid of @djWaitCount and uid not of @vips and @djWaitCount[uid] <= @get_config('wait_songs')
              waitSongs = @get_config('wait_songs') - @djWaitCount[uid]
              @bot.speak "#{user.name}, party foul! Wait #{waitSongs} more song#{plural(waitSongs)} before getting on the decks again!"
              
              if @selfModerator
                # Escort off stage
                @ensure_escort(uid)
        else if @room_mode is VIP_MODE
          if not (uid of @vips or @is_mod(uid) or @is_owner(uid))
            if @selfModerator
              # Escort off stage
              @ensure_escort(uid)
            @bot.speak "#{user.name}, it's VIPs only on deck right now!"
    #    else if @room_mode is BATTLE_MODE
        
      # Resume song count if DJ rejoined too quickly
      if uid of @pastDjSongCount and elapsed(@pastDjSongCount[uid].when) < @get_config('djs_resume_count_interval') * MINUTE
        @djSongCount[uid] = @pastDjSongCount[uid].count
      else
        @djSongCount[uid] = 0
      
      @db_col 'djs', (col)=>
        criteria =
          'userInfo.userid': uid
        modifications =
          '$set':
            'userInfo': user
            'onstage': true
            'left': now()
            'count': @djSongCount[uid]
        col.update criteria, modifications, {upsert: true}

    @bot.on "rem_dj", (data) =>
      user = data.user[0]
      uid = user.userid
      
      @db_col 'djs', (col)=>
        criteria =
          'userInfo.userid': uid
        modifications =
          '$set':
            'userInfo': user
            'onstage': false
            'left': now()
        col.update criteria, modifications, {upsert: true}
      
      # Add to timeout list if DJ has played 
      if @limits_enabled and @djSongCount[uid] >= @get_config('max_songs') and not @djWaitCount[uid]
        # I believe the new song message is triggered first. Could ignore the message if it is too soon
        @djWaitCount[uid] = 0
        
      # TODO consider lineskipping
      @pastDjSongCount[uid] = { count: @djSongCount[uid], when: new Date() }
      delete @djSongCount[uid]
      delete @campingDjs[uid]
      delete @warnedDjs[uid]
    
    @bot.on "snagged", (data) =>
      @debug "Heart: #{@roomUsers[data.userid].name} to #{@currentDj.name}"
      @track_action("hearts", @roomUsers[data.userid], @currentDj)
    
    greetings = greet.greetings  
    
    get_greeting = (user) =>
      greeting = null
    
      if user.name of greetings
        greeting = greetings[user.name]
      else if user.userid of greetings
        greeting = greetings[user.userid]
      
      if greeting
        if typeof greeting is "function"
          greeting = greeting(user)
        return greeting
    
    heartbeat = =>
      # Escort AFK DJs
      for uid in _.keys(@djSongCount)
        if uid of @lastActivity
          idle = elapsed(@lastActivity[uid])
          
          if idle > @get_config('dj_warn_time') * MINUTE and uid not of @warnedDjs
            @bot.speak "#{@roomUsers[uid].name}, no falling asleep on deck!"
            @warnedDjs[uid] = true
          if idle > @get_config('dj_escort_time') * MINUTE
            if uid isnt @currentDj?.userid and not @is_vip(uid) and not @is_mod(uid) and not @is_owner(uid)
              @ensure_escort(uid)
        else
          @lastActivity[uid] = now()
      
      @capacity_boot()
    
    setInterval heartbeat, 1000
        
    @bot.on "registered", (data) =>
      if data.user[0].userid is @userId
        # We just joined, initialize things
        @roomInfo (data) =>
          # Initialize users
          _.map(data.users, @register)
          
          # Initialize dj counts
          for uid in data.room.metadata.djs
            @djSongCount[uid] = 0
          
          if @currentDj? and @currentDj.userid of @roomUsers
            @djSongCount[@currentDj.userid] = 1
            
            @lastDj = @roomUsers[@currentDj.userid]
          
          # Check if we are moderator
          @selfModerator = _.any(data.room.metadata.moderator_id, (id) => id is @userId)
          
          for uid in data.room.metadata.moderator_id
            @mods[uid] = true
      
      _.map(data.user, @register)

      user = data.user[0]
      @userCount += 1
      @capacity_boot()
      
      @db_col 'login', (col) =>
        record =
          'userInfo': user
          'when': now()
        col.insert record
        @debug "Logging #{user.name} registering"
      
      if user.userid of @permabanned
        if @selfModerator
          @bot.bootUser(user.userid, @permabanned[user.userid])
          return
        else
          @bot.speak "I can't boot you, #{user.name}, but you've been banned for #{@permabanned[user.userid]}"
      
      # Only say hello to people that have left more than REJOIN_MESSAGE_WAIT_TIME ago
      if _.keys(@active).length <= @get_config('greetings_max_capacity') and @get_config('greetings') and user.userid isnt @userId and (not @roomUsersLeft[user.userid] or elapsed(@roomUsersLeft[user.userid]) > @get_config('rejoin_greeting_interval') * SECOND)
        if greeting = get_greeting(user)
          delay = =>
            if user.userid of @active
              @bot.speak greeting
          
          setTimeout delay, @get_config('special_greeting_delay') * SECOND
        else if user.userid of @vips
          delay = =>
            if user.userid of @active
              @bot.speak "Welcome #{user.name}, we have a VIP aboard the PARTY BUS!"

          setTimeout delay, @get_config('special_greeting_delay') * SECOND
        else if user.acl > 0
          delay = =>
            if user.userid of @active
              @bot.speak "We have a superuser in the HOUSE! #{user.name}, welcome aboard the PARTY BUS!"

          setTimeout delay, @get_config('special_greeting_delay') * SECOND
        else
          @joinedUsers[user.userid] = user
          
          delay = ()=>
            greet_users = _.filter(@joinedUsers, (user) => user.userid of @active)
            
            if greet_users.length > 0
              users_text = (user.name for user in greet_users).join(", ")
              
              @bot.speak "Hello #{users_text}, welcome aboard the PARTY BUS!"
            
            @joinedUsers = {}
            @greetingTimeout = null

          if not @greetingTimeout
            @greetingTimeout = setTimeout delay, @get_config('greeting_delay') * SECOND
      
      for user in data.user
        # Double join won't spam
        @roomUsersLeft[user.userid] = new Date()
    
    @bot.on "update_user", (data) =>
      # Track name changes
      if data.name
        @update_name(data.userid, data.name)
    
    @bot.on "deregistered", (data) =>
      user = data.user[0]
      @userCount -= 1
      delete @active[user.userid]
      @roomUsersLeft[user.userid] = new Date()
    
    # Add and remove moderator
    @bot.on "new_moderator", (data) =>
      if data.success
        if data.userid is @userId
          @selfModerator = true
        else
          @mods[data.userid] = true
    
    @bot.on "rem_moderator", (data) =>
      if data.success
        if data.userid is @userId
          @selfModerator = false
        else
          delete @mods[data.userid]
    
    rl = readline.createInterface(process.stdin, process.stdout)
        
    rl.on "line", (line) =>
      [cmd_txt, args] = command(line)

      user = @roomUsers[@selfId]
      
      matcher = cmd_matches(cmd_txt)
      out = (txt) => util.puts txt
      
      if resolved_cmd = _.find(@cli_commands, matcher)
        resolved_cmd.fn(user, args, out)
      else if resolved_cmd = _.find(@commands, matcher)
        resolved_cmd.fn(user, args, out)
    
    rl.on "close", =>
      process.stdout.write '\n'
      process.exit 0
    
    @bot.on "speak", (data) =>
      @update_name(data.name, data.userid)
      @update_idle(data.userid)
      [cmd_txt, args] = command(data.text)
      user = @roomUsers[data.userid]
      
      resolved_cmd = _.find(@commands, cmd_matches(cmd_txt))
      
      if resolved_cmd and @allowed_cmd(user, resolved_cmd)
        if logged_cmd(resolved_cmd)
          util.puts "MOD #{now().toTimeString()}: #{data.name}: #{data.text}"
          @db_col 'commands', (col)=>
            col.insert
              user: user
              cmd: cmd_txt
              args: args
              when: new Date()
        resolved_cmd.fn(user, args, (txt) => @bot.speak(txt))
      
      if @chat_enabled
        util.puts "#{data.name}: #{data.text}"
      
      @chat_action user, cmd_txt, args

      @db_col 'chat', (col)=>
        col.insert data
    
    # Commands
    @commands = [
      {cmd: "/allowed", fn: @cmd_allowed, help: "allowed djs"}
      {cmd: "/album", fn: @cmd_album, help: "current song album"}
      {cmd: "/ball", name: "/ball so hard", fn: @cmd_ballsohard, spam: true, help: "ball so hard"}
      {cmd: "/commands", fn: @cmd_commands, hidden: true, help: "get list of commands"}
      {cmd: "/dance", fn: @cmd_dance, help: "dance!"}
      {cmd: "/daps", fn: @cmd_daps, spam: true, help: "daps"}
      {cmd: "/djs", fn: @cmd_throttled_djs, help: "dj song count"}
      {cmd: "/hearts", fn: @cmd_hearts, spam: true, help: "get hearts count"}
      {cmd: "/hugs", fn: @cmd_hugs, spam: true, help: "get hugs count"}
      {cmd: ["/help", "/rules", "/?"], name: "/help", fn: @cmd_help, help: "get help"}
      {cmd: ["/last", "/prev", "/last_song", "/prev_song"], name: "/last", fn: @cmd_last_song, help: "votes for the last song"}
      {cmd: "/mods", fn: @cmd_mods, help: "lists room mods"}
      {cmd: "/party", fn: @cmd_party, spam: true, help: "party!"}
      {cmd: "/power", fn: @cmd_power, spam: true, help: "checks the power level of a user using the scouter"}
      {cmd: ["q", "/q", "/queue", "q?", "list"], name: "/queue", fn: @cmd_queue, hidden: true, help: "get dj queue info"}
      {cmd: "q+", fn: @cmd_queue_add, hidden: true, help: "add to dj queue"}
      {cmd: "/ragequit", fn: @cmd_ragequit, help: "ragequit"}
      {cmd: ["/timeout", "/wait", "/waiting", "/waitlist"], name: "/timeout", fn: @cmd_waiting, help: "dj timeout list"}
      {cmd: "/users", fn: @cmd_users, help: "counts room users"}
      {cmd: "/stagedive", fn: @cmd_stagedive, help: "stage dive!"}
      {cmd: "/vips", fn: @cmd_vips, help: "list vips in the bus"}
      {cmd: "/vuthers", fn: @cmd_vuthers, spam: true, help: "vuther clan roll call"}
      {cmd: "/d-_-bs", fn: @cmd_dbs, spam: true, help: "d-_-b's roll call"}
      
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
    
    @cli_commands = [
      {cmd: "/chat", fn: @cmd_chat, help: "make the bot say something"}
      {cmd: "/togglechat", fn: @cmd_togglechat, help: "view chat"}
      {cmd: "/debug", fn: @cmd_debug, help: "enable/disable debug"}
      {cmd: "/djs", fn: @cmd_djs, help: "dj song count"}
      {cmd: "/name", fn: @cmd_rename, help: "change bot name"}
      {cmd: "/whoami", fn: @cmd_whoami, help: "check who the bot is"}
    ]

  track_action: (action, user, target) =>
    if not @actions[action][user.userid]?
      @actions[action][user.userid] =
        given: 1
        received: 0
    else
      @actions[action][user.userid].given += 1
    
    @db_col 'actions', (col)=>
      criteria =
        'userInfo.userid': user.userid
        'action': action
      modifications =
        '$set':
          'userInfo': user
        '$inc':
          'given': 1
      col.update criteria, modifications, {upsert: true}
    
    if not @actions[action][target.userid]?
      @actions[action][target.userid] =
        given: 0
        received: 1
    else
      @actions[action][target.userid].received += 1    
    
    @db_col 'actions', (col)=>
      criteria =
        'userInfo.userid': target.userid
        'action': action
      modifications =
        '$set':
          'userInfo': target
        '$inc':
          'received': 1
      col.update criteria, modifications, {upsert: true}
    
  chat_action: (issuer, cmd, arg) =>
    if cmd is "/me"
      [cmd, arg] = command(arg)
    
    action = norm(cmd)
    
    if _.include(@tracked_actions, action)
      if target = @get_by_name(arg)
        if target.userid isnt issuer.userid
          @track_action(action, issuer, target)

  allowed_cmd: (issuer, cmd) =>
    @is_owner(issuer.userid) or (not cmd.owner and (@is_mod(issuer.userid) or not cmd.mod))
  
  logged_cmd = (cmd) =>
    cmd.owner or cmd.mod
  
  cmd_matches = (txt) =>
    matches = (cmd) =>
      if typeof cmd is "string"
        if cmd is txt
          true
      else if "length" of cmd
        _.find(cmd, matches)
      else if typeof cmd is "function" and cmd.test(txt)
        true
    
    (entry) => matches(entry.cmd)
  
  cmd_debug: (issuer, args) =>
    arg = norm(args)
    if arg is "true" or arg is "on"
      util.puts "Debug mode enabled!"
      @debug_on = true
    else
      util.puts "Debug mode OFF"
      @debug_on = false
  
  cmd_rename: (issuer, args, out) =>
    args = args.trim()
    
    if args isnt ""
      check = (data) =>
        if data.success
          out "Changed name to #{args}!"
        else
          out "Failed to change name: #{data.err}"
      
      @bot.modifyName(args, check)
    else
      out "You have to give a name!"
  
  cmd_chat: (issuer, args) =>
    @bot.speak args.trim()
  
  cmd_whoami: (user, args, out) =>
    if options.userId of @roomUsers
      out "Logged in as #{@roomUsers[options.userId].name}"
    else
      out "Couldn't find myself"
  
  cmd_togglechat: =>
    @chat_enabled = not @chat_enabled
  
  # Commands
  cmd_last_song: =>
    if @lastScore isnt ""
      @bot.speak "The previous song: #{@lastScore}"
    else
      @bot.speak "I blacked out and forgot what the last song was."
  
  cmd_album: =>
    @roomInfo (data) =>
      if @album isnt ""
        @bot.speak "Song album: #{@album}"
      else
        @bot.speak "What album?"
  
  cmd_boot: (issuer, args) =>
    if @selfModerator
      boot_pat = /^\s*(.*?)\s*:\s*([^\s].+?)\s*$/
      
      if match = boot_pat.exec(args)
        name = match[1]
        reason = match[2]
        
        if uid = @get_uid(name)
          if uid is @userId
            @bot.speak "I'm not booting myself!"
          else
            @bot.bootUser(uid, reason)
        else
          @bot.speak "I couldn't find #{name} to boot!"
      else
        @bot.speak "#{issuer.name} you have to give a reason to boot!"
    else
      @bot.speak "I'm powerless, do it yourself!"
  
  cmd_escort: (issuer, args) =>
    if @selfModerator
      if dj = @get_dj(args)
        @bot.remDj(dj)
    else
      @bot.speak "I'm powerless, do it yourself!"
  
  cmd_allow: (issuer, args, out) =>
    if target = @get_by_name(args)
      if target.userid not of @allowed
        @allowed[target.userid] = target
        @bot.speak "#{target.name}, get up on deck!"
        
        @db_col 'users', (col)=>
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
  
  cmd_unallow: (issuer, args) =>
    if user = @get_by_name(args)
      if user.userid of @allowed
        @bot.speak "#{user.name} is no longer on the allowed DJ list"
        delete @allowed[user.userid]
        @db_col 'users', (col)=>
          criteria =
            'userInfo.userid': user.userid
          modifications =
            '$set':
              'userInfo': user
              'allowed': false
          col.update criteria, modifications, {upsert: true}
      else
        @bot.speak "#{user.name} is not on the allowed DJ list!"
    else
      out "I couldn't find #{args} to remove from the allowed DJ list!"
  
  cmd_allowed: (issuer, args, out) =>
    args = norm(args)
    
    users = _.filter(@allowed, (user) => user.userid not of @vips)
    
    if args is "all"
      msg = ""
      
      if users.length > 0
        allowed_list = (user.name for user in users).join(", ")
        msg += "All allowed DJs: #{allowed_list}"
      else if _.keys(@vips).length == 0
        msg += "There is no one on the allowed DJs list!"
      
      if _.keys(@vips).length > 0
        vip_list = (user.name for uid, user of @vips).join(", ")
        msg += " VIPs: #{vip_list}"
      
      out msg
    else
      present_users = _.filter(users, (user) => user.userid of @active)
      present_vips = _.filter(@vips, (user) => user.userid of @active)
      
      msg = ""
      
      if present_users.length > 0
        allowed_list = (user.name for user in present_users).join(", ")
        msg += "Allowed DJs: #{allowed_list}"
      else if present_vips.length == 0
        msg += "There are no allowed DJs in the Party Bus right now"
  
      if present_vips.length > 0
        vip_list = (user.name for user in present_vips).join(", ")
        msg += " VIPs: #{vip_list}"
      
      out msg
  
  cmd_vip: (issuer, args, out) =>
    if user = @get_by_name(args)
      if user.userid not in _.keys @vips
        @vips[user.userid] = user
        @bot.speak "Party all you want, #{user.name}, because you're now a VIP!"

        @db_col 'users', (col)=>
          criteria =
            'userInfo.userid': user.userid
          modifications =
            '$set':
              'userInfo': user
              'vip': true
          col.update criteria, modifications, {upsert: true}
      else
        @bot.speak "#{user.name} is already a VIP on the Party Bus!"
    else
      out "I couldn't find #{args} in the bus to make a VIP!"
  
  cmd_unvip: (issuer, args) =>
    user = @get_by_name(args)
    
    if user and user.userid of @vips
      @bot.speak "#{user.name} is no longer special"
      delete @vips[user.userid]

      @db_col 'users', (col)=>
        criteria =
          'userInfo.userid': user.userid
        modifications =
          '$set':
            'userInfo': user
            'vip': false
        col.update criteria, modifications, {upsert: true}
    else
      @bot.speak "#{args} is not a VIP in the Party Bus!"
  
  cmd_vips: (issuer, args, out) =>
    args = norm(args)
    if args is "all"
      if _.keys(@vips).length > 0
        vip_list = (user.name for uid, user of @vips).join(", ")
        out "All VIPs in the Party Bus: #{vip_list}"
      else
        out "There are no VIPs in the Party Bus right now"
    else
      present_vips = _.filter(@vips, (user) => user.userid of @active)
      
      if present_vips.length > 0
        vip_list = (user.name for user in present_vips).join(", ")
        out "Current VIPs in the Party Bus are #{vip_list}"
      else
        out "There are no VIPs in the Party Bus right now"
  
  ###
  Dance Commands
  ###
  
  cmd_ballsohard: (issuer, args) =>
    if norm(args) is "so hard"
      if @get_config('chat_spam')
        @bot.speak "Muhfuckas wanna fine me!"
      @bot.vote "up"
  
  cmd_party: (issuer, args) =>
    if @get_config('chat_spam')
      if norm(args) is "on wayne"
        @bot.speak "Party on Garth!"
      else
        @bot.speak "AWWWWWW YEAHHHHHHH!"
    
    @bot.vote "up"
  
  dances = [
    "Erryday I'm Shufflin'"
    "/me dances"
    "Teach me how to dougie!"
    "/me dougies"
    ]
  
  cmd_dance: => 
    if @get_config('chat_spam')
      @bot.speak random_select(dances)
    @bot.vote "up"

  ###
  Fun Commands
  ###
  
  cmd_daps: (issuer) =>
    if @get_config('chat_spam')
      name = issuer.name
      
      if name is "marinating minds"
        name = "SAUCEY"
      
      @bot.speak "DAPS #{name}"

  cmd_ragequit: (issuer) =>
    if @get_config('chat_spam')
      @bot.speak "Lol umadbro?"
    @bot.bootUser(issuer.userid, "gtfo")
  
  cmd_vuthers: =>
    if @get_config('chat_spam')
      @roomInfo (data) =>
        vuther_pat = /\bv[aeiou]+\w*th[aeiou]\w*r/i
        
        daddy = false
        
        is_vutherbot = (name) =>
          if name is "vuther"
            daddy = true
            return false
          else
            return vuther_pat.test(name)
        
        vuthers = _.select(data.users, (user) => is_vutherbot(user.name))
        vuthers = _.map(vuthers, (user) => user.name)
        
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
  
  cmd_dbs: =>
    if @get_config('chat_spam')
      @roomInfo (data) =>
        db_pat =  /.*d.*?_.*?b.*/i
        
        daddy = false
        
        is_db = (name) =>
          if name is "d-_-b"
            daddy = true
            return false
          else
            return db_pat.test(name)
        
        dbs = _.select(data.users, (user) => is_db(user.name))
        dbs = _.map(dbs, (user) => user.name)
        
        msg = "d-_-b team, ASSEMBLEEEE!"
        
        if dbs.length > 0
          msg += " There are #{dbs.length} soldier#{plural(dbs.length)} in the d-_-b army here: " + dbs.join(", ") + "."
        else
          msg += " There are no d-_-bs here..."
        
        if daddy
          if dbs.length > 0
            msg += " And d-_-b is here!"
          else
            msg += " But d-_-b is here!"
        
        @bot.speak msg
    
  ###
  DJ info commands
  ###
  
  cmd_throttled_djs: (user, args, out) =>
    if not @djs_last? or now().getTime() - @djs_last.getTime() > @get_config('cmd_djs_throttle_time')
      @cmd_djs(user, args, out)
  
  cmd_djs: (user, args, out) =>
    if _.keys(@djSongCount).length == 0
      out "I don't have enough info yet for a song count"
    else
      txt = "Song Totals: "
      @roomInfo (data) =>
        newDjSongCount = {}
        
        for dj in data.room.metadata.djs
          newDjSongCount[dj] = @djSongCount[dj] or 0
        
        @djSongCount = newDjSongCount
        
        out (txt + ("#{@roomUsers[dj].name}: #{count}" for dj, count of @djSongCount).join(", "))

  cmd_waiting: =>
    if _.keys(@djWaitCount).length == 0
      @bot.speak "No DJs are in the naughty corner!"
    else
      waiting_list = ("#{@roomUsers[dj].name}: #{@get_config('wait_songs') - count}" for dj, count of @djWaitCount).join(", ") + " songs"
      @bot.speak "DJ naughty corner: #{waiting_list}"
  
  cmd_queue: (issuer, args) =>
    if @get_config('chat_spam')
      if @room_mode is VIP_MODE
        @bot.speak "#{issuer.name}, the Party Bus has no queue! It's VIPs (and mods) only on deck right now!"
      else if @room_mode is BATTLE_MODE
        @bot.speak "#{issuer.name}, the Party Bus has no queue! It's a King of the Hill battle right now!"
      else if @room_mode is NORMAL_MODE
        if not @queueEnabled
          @bot.speak "#{issuer.name}, the Party Bus has no queue! It's FFA, #{@get_config('max_songs')} song limit, #{@get_config('wait_songs')} song wait time"
  
  cmd_queue_add: (issuer, args) =>
    @cmd_queue(issuer, args)
        
  ###
  Room info commands
  ###
  
  cmd_mods: =>
    @roomInfo (data) =>
      # Collect mods
      mod_list = (@roomUsers[uid].name for uid in data.room.metadata.moderator_id when @active[uid] and uid isnt @userId and uid not in @excluded_mods).join(", ")
      @bot.speak "Current mods in the Party Bus are #{mod_list}"
  
  cmd_users: =>
    @roomInfo (data) =>
      count = _.keys(data.users).length
      @bot.speak "There are #{count} peeps rocking the Party Bus right now!"
  
  cmd_help: (issuer, args) =>
    if @room_mode is VIP_MODE
      @bot.speak "Hey #{issuer.name}, welcome aboard the party bus. Read the room rules: #{@get_config('rules_link')}. It's VIPs (and mods) only on deck right now!"
    else if @room_mode is BATTLE_MODE
      @bot.speak "Hey #{issuer.name}, welcome aboard the party bus. Read the room rules: #{@get_config('rules_link')}! It's a King of the Hill battle right now!"
    else if @room_mode is NORMAL_MODE
      @bot.speak "Hey #{issuer.name}, welcome aboard the party bus. Read the room rules: #{@get_config('rules_link')}"
  
  cmd_commands: =>
    cmd_hidden = (cmd) =>
      cmd.hidden or cmd.owner or cmd.mod or (not @get_config('chat_spam') and cmd.spam)
    
    cmds = _.select(@commands, (cmd) => not cmd_hidden(cmd))
    cmds_text = _.map(cmds, (entry) => entry.name or entry.cmd).join(", ")
    
    @bot.speak cmds_text
  
  cmd_setsongs: (user, args) =>
    setsongs_pat = /^(.+?)\s+(-?\d+)\s*$/
    
    if match = setsongs_pat.exec(args)
      name = match[1]
      count = parseInt(match[2])
      
      if dj = @get_dj(name)
        @djSongCount[dj] = count
        
        # Set camping if over
        if count >= @get_config('max_songs') and dj not of @campingDjs
          @campingDjs[dj] = 0
        
        # Remove camping if under
        if count < @get_config('max_songs') and dj of @campingDjs
          delete @campingDjs[dj]
  
  cmd_resetdj: (user, args) =>
    if djUser = @get_by_name(args)
      if @uid_is_dj(djUser.userid)
        @djSongCount[djUser.userid] = 0
      
      delete @campingDjs[djUser.userid]
      delete @djWaitCount[djUser.userid] 
  
  cmd_off: =>
    @limits_enabled = false
    @bot.speak "Party all you want, because DJ limits are off!"
  
  cmd_on: =>
    @limits_enabled = true
    @bot.speak "DJ limits are enabled again"
  
  cmd_uid: (issuer, args, out) =>
    if user = @get_by_name(args)
      out user.userid
  
  cmd_permaban: (issuer, args) =>
    boot_pat = /^\s*(.*?)\s*:\s*([^\s].+?)\s*$/
    
    if match = boot_pat.exec(args)
      uid = undefined
      name = match[1]
      reason = match[2]
    
      if is_uid(name)
        uid = name
      else if user = @get_by_name(name)
        uid = user.userid
        name = user.name
        
      if uid
        if uid is @userId
          @bot.speak "I'm not booting myself!"
        else
          if @selfModerator
            @bot.bootUser(uid, reason)
            @bot.speak "Banning #{name}"
          else
            @bot.speak "I'm powerless to ban anyone, but #{name} is on the list!"
                  
          @permabanned[uid] = reason
    else
      @bot.speak "#{issuer.name} you have to give a reason to ban someone!"
  
  cmd_unpermaban: (issuer, args) =>
    query = norm(args)
    
    if is_uid(query) and query of @permabanned
      delete @permabanned[query]
      @bot.speak "Unbanning #{@roomUsers[query].name}"
    else if user = @get_by_name(query)
      delete @permabanned[user.userid]
      @bot.speak "Unbanning #{@roomUsers[user.userid].name}"
  
  cmd_chinesefiredrill: (issuer, args) =>
    @roomInfo (data) =>
      if @selfModerator and args is "THIS IS ONLY A DRILL"
        @bot.speak "CHINESE FIRE DRILL! In 3"
        
        callback = =>
          for uid in data.room.metadata.djs
            @bot.remDj(uid)
          @bot.bootUser(issuer.userid, "for pulling the fire alarm")
        
        it = (i) => @bot.speak(i)
        delay_countdown(callback, it, 2)
      else
        @bot.speak "CHINESE FIRE DRILL DRILL! In 3"
        
        msg = => @bot.speak "Escorting " + (@roomUsers[dj].name for dj in data.room.metadata.djs).join(", ") + " and booting #{issuer.name} for pulling the fire alarm."
        it = (i) => @bot.speak(i)
        delay_countdown(msg, it, 2)
  
  cmd_power: (issuer, args) =>
    if @get_config('chat_spam')
      @roomInfo (data) =>
        name = norm(args)
        
        if name isnt ""
          # Initialize users
          if user = _.find(data.users, (user) => norm(user.name) is norm(args))
            power = Math.floor(user.points / 1000)
            if power > 0
              @bot.speak "Vegeta, what does the scouter say about #{user.name}'s power level? It's over #{power}000!!!"
            else
              @bot.speak "#{user.name} doesn't have much of a power level..."
          else
            @bot.speak "The scouter couldn't find anyone named #{args}!"
        else
          @bot.speak "Who?"
  
  cmd_night: =>
    @set_config('wait_songs', @get_config('wait_songs_night'))
    
    @bot.speak "It's late at night! DJs wait #{@get_config('wait_songs')} songs"
    
    for dj, count of @djWaitCount
      if count > @get_config('wait_songs')
        delete @djWaitCount[dj]
  
  cmd_day: =>
    @set_config('wait_songs', @get_config('wait_songs_day'))
    
    @bot.speak "It's bumping in here! DJs wait #{@get_config('wait_songs')} songs"
  
  cmd_stagedive: (issuer) =>
    if @uid_is_dj(issuer.userid)
      @bot.remDj(issuer.userid)
      @bot.speak "#{issuer.name}, go crowd surfing!"
      
  cmd_boost: (issuer, args) =>
    if norm(args) is "off"
      @boost = off
      
      if @get_config('chat_spam')
        @bot.speak "No more rocket boost!"
    else
      @boost = on
      
      @bot.speak "VIPs and allowed DJs, get up on deck!"
  
  cmd_set: (issuer, args, out) =>
    [key, value] = command(args)
    
    @set_config(key, value)
  
  cmd_get: (issuer, args, out) =>
    [x] = command(args)
    
    if x? and x of @config_props
      props = @config_props[x]
    
      result = @config[x] ? props.default
      
      result = if props.format? and (pretty = @config_format[props.format]?.pretty)? then pretty(result, props.unit) else result
      
      out "#{props.name}: #{result}"
  
  cmd_hearts: (issuer, args) =>
    if @get_config('chat_spam')
      if args is "given"
        count = @actions["hearts"][issuer.userid]?.given ? 0
        
        if count == 0
          @bot.speak "#{issuer.name} is incapable of love"
        else
          @bot.speak "You have given #{count} heart#{plural(count)}"
      else if args is "top"
      else
        count = @actions["hearts"][issuer.userid]?.received ? 0
        
        if count == 0
          @bot.speak "#{issuer.name} is a heartless bastard"
        else
          @bot.speak "#{issuer.name}, you have #{count} heart#{plural(count)}"
  
  cmd_hugs: (issuer, args) =>
    if @get_config('chat_spam')
      if args is "given"
        count = @actions["hugs"][issuer.userid]?.given ? 0
        
        if count == 0
          @bot.speak "#{issuer.name} is afraid of human intimacy"
        else
          @bot.speak "#{issuer.name}, you've given #{count} hug#{plural(count)}"
      else if args is "top"
      else
        count = @actions["hugs"][issuer.userid]?.received ? 0
        
        if count == 0
          @bot.speak "#{issuer.name}, you have no hug points and nobody loves you"
        else
          @bot.speak "You have #{count} hug point#{plural(count)} :)"

exports.BusDriver = BusDriver

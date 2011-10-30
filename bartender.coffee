Bot = require 'ttapi'
irc = require 'irc'
_un = require 'underscore'
util = require 'util'


bartender = (userAuth, selfId, roomId, ircServer, ircChan, ircHandle="bartender") ->
  if not userAuth
    util.puts("User auth token required")
    util.exit
  
  if not selfId
    util.puts("User id token required")
    util.exit
  
  if not roomId
    util.puts("Room id token required")
    util.exit
  
  bot = new Bot userAuth, selfId, roomId

  ircClient = new irc.Client ircServer, ircHandle, 
    channels: [ircChan]
  
  roomUsernames = {}
  roomUsers = {}
  
  plural = (count) ->
    if count == 1
      's'
    else
      ''
  
  random_select = (list) ->
    list[Math.floor(Math.random()*list.length)]
  
  bot.on "registered", (data) ->
    if data.user[0].userid is selfId
      # We just joined, initialize things
      bot.roomInfo (data) ->
        # Initialize users
        for user in data.users
          roomUsernames[user.name] = user
          roomUsers[user.userid] = user
    
    for user in data.user
      roomUsernames[user.name] = user
      roomUsers[user.userid] = user
  
  cmd_drinks = (user) ->
    msgs = [
      "This party is bumping! Drinks all around!"
      "Hey #{user.name}, here's a little something to get you rocking!"
      "Martini, shaken, not stirred."
      "Scotch neat"
      "Jager bombs! Jager bombs!"
      "Hey #{user.name}, I think you might have had a little too much to drink"
      "Tequila sunrise for you"
      "Here's an Adios Mother F***er. Say 'adios!'"
      "We've got a great selection of beer here."
      "A cape cod huh. Is it that time of the month?"
      "Here's some hard cider"
      "#{user.name}, do you need me to call a cab"
      "Ah a Belgian. How about the St. Bernardus 12"
      "Irish Car Bomb for you"
      "Hey #{user.name}, here's a White Russian"
      "Some wine, perhaps?"
      "Here's a Flaming Doctor Pepper!"
      "Margarita coming right up"
      "We've got a great selection on this bus!"
      "/me wipes a glass"
      "/me cuts a lime"
    ]
    bot.speak random_select(msgs)
    bot.vote "up"
  
  # TODO, match regexes, and have a hidden, so commands automatically lists
  commands = [
    {cmd: "/drinks", fn: cmd_drinks, help: "drinks"}
  ]
  
  bartender.commands = commands
  
  command = (data) ->
    cmd_pat = /^([^\s]+?)(\s+([^\s]+.+?))?\s*$/
    
    cmd = ""
    args = ""
    
    if match = cmd_pat.exec(data.text)
      cmd = match[1].toLowerCase()
      args = match[3] or ""
    
    [cmd, args]
  
  bot.on "speak", (data) ->
    [cmd_txt, args] = command(data)
    user = roomUsers[data.userid]
    
    cmd_matches = (entry) ->
      if typeof entry.cmd == "string" and entry.cmd is cmd_txt
        return true
      if typeof entry.cmd == "function" and entry.cmd.test(cmd_txt)
        return true
    
    resolved_cmd = _un.detect(commands, cmd_matches)
    
    if resolved_cmd
        resolved_cmd.fn(user, args)
  
exports.bartender = bartender
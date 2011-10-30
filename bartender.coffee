Bot = require 'ttapi'
_un = require 'underscore'
util = require 'util'


bartender = (userAuth, selfId, roomId) ->
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
  
  roomUsernames = {}
  roomUsers = {}
  
  plural = (count) ->
    if count == 1
      's'
    else
      ''
  
  random_select = (list) ->
    list[Math.floor(Math.random()*list.length)]
  
  scotches = [
    "Highland Park 12"
    "Highland Park 15"
    "Johnny Walker Black Label"
    "Johnny Walker Blue Label"
    "Johnny Walker Gold Label"
    "Laphroaig 10"
    "Laphroaig 16"
    "Laphroaig 18"
    "Laphroaig Quarter Cask"
    "Lagavulin 16"
    "Macallan 10"
    "Macallan 12 Fine Oak"
    "Macallan 15 Fine Oak"
    "Macallan 18 Fine Oak"
    ]
  
  special_drinks = 
    "beer": "Tap specials today are the Rogue Dead Guy Ale and the Pyramid Hefeweizen (or do you drink Bud Light?)"
    "wine": "Here, try some of our finest Chardonnay!"
    "vodka": "One double of Stoli on the rocks, coming right up!"
    "scotch": -> "/me pours a double of " + random_select(scotches)
    "gin & tonic": "Here's a Gin & Tonic! Would you like some lime in that?"
    "amf": "Say 'Adios', motherf*cker!"
    "4loko": "Are you ready to get SLAMMED?"
    "natty": "Alright, one 'beer' coming right up..."
    "coors": "CHUG! CHUG! CHUG! CHUG!"
    "redbull & vodka": "Party it up in hurrrrrr"
    "soda": ["Mmm, nothing like a Coca-Cola", "Why not take a break and have some Sprite", "OK, here's a Dr. Pepper"]
    "pop": "Are you sure you didn't mean a SODA?"
    "keg": "Are you sure that isn't a bit much for one person?"
    
    
  bot.on "registered", (data) ->
    if data.user[0].userid is selfId
      # We just joined, initialize
      bot.roomInfo (data) ->
        # Initialize users
        for user in data.users
          roomUsernames[user.name] = user
          roomUsers[user.userid] = user
    
    for user in data.user
      roomUsernames[user.name] = user
      roomUsers[user.userid] = user
  
  cmd_drinks = (user, args) ->
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
      "/me ices #{user.name}"
      "/me wipes a glass"
      "/me cuts a lime"
    ]
    
    lcDrink = args.toLowerCase()
    
    selection = null
    
    if lcDrink of special_drinks
      selection = special_drinks[lcDrink]
      if typeof selection is "object"
        selection = random_select(selection)
    else
      selection = random_select(msgs)
    
    if typeof selection is "function"
      selection = selection()
    
    bot.speak selection
    
    bot.vote "up"
  
  # Match regexes
  commands = [
    {cmd: /^\/drinks?$/, fn: cmd_drinks, help: "drinks"}
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
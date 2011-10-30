Bot = require 'ttapi'
_un = require 'underscore'
util = require 'util'
r = require 'mersenne'


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
    list[r.rand(list.length)]
  
  drinks_scotches = [
    "Aberlour 12"
    "Bowmore Darkest Sherry Finish"
    "Glenmorangie 18"
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
  
  drinks_sodas = [
    "7-Up"
    "Coca-Cola"
    "Diet Coke"
    "Dr. Pepper"
    "Fanta"
    "Ginger Ale"
    "Sprite"
  ]
  
  drinks_beers = [
    "Allagash Triple Reserve"
    "Deschutes Abyss"
    "Dogfish Head 90-Minute IPA"
    "Dogfish Head Midas' Touch"
    "Dogfish Head Punkin Ale"
    "Gorden Biersch Pilsner"
    "Green Flash West Coast IPA"
    "Heineken"
    "Lagunitas India Pale Ale"
    "North Coast Rasputin Imperial Stout"
    "Pyramid Hefeweizen"
    "Rogue Dead Guy Ale"
    "Samuel Smith Oatmeal Stout"
    "Spaten Optimator Dark"
    "Stone Leviation Pale Ale"
    "Stone Ruination"
  ]
  
  
  drinks_crappy_beers = [
    "Bud Light"
    "Budweiser"
    "Coors"
    "Coors Light"
    "Keystone"
    "Keystone Ice"
    "Keystone Light"
    "Miller"
    "Miller Lite"
    "Natty"
    "Natty Light"
  ]
  
  drinks_wines = [
    "Vanel Sauvignon Blanc '10"
    "Sonoma Hills Chardonnay '09"
    "Yellow Tail Shiraz '08"
    "Keenan Chardonnay '08"
    "La Crema Chardonnay '09"
    "Fratelli Casa Rossa"
    "Paul Masson Rhine Castle"
    "Ch Ste Michelle Cabernet '08"
    "Kendall-Jackson Cabernet Grand Res '07"
    "Cinnabar Mercury Rising '08"
    "Zinnia Pinot Noir Reserve '10"
    "Tikal Patriota '09"
    "Tedeschi Maui Blanc Pineapple Wine"
    "Salon Champagne '97"
    "Dominus '08"
    "Robert Hall Syrah '08"
    "Altocedro Malbec Grand Reserva '08"
    "Catena Zapata '07"
    "Louis Roederer Cristal Brut '02"
    "Joseph Perrier Champagne Josephine '02 "
    "Ch Cos d'Estournel '05 St Estephe"
    "Heitz Cab Martha's 06"
  ]
  
  n_beers = drinks_beers.length
  beers_on_tap = ->
    i = r.rand(n_beers)
    j = r.rand(n_beers-1)
    k = (i + j) % n_beers
    "Tap specials are the " + drinks_beers[i] + " and the " + drinks_beers[k] + ", or are you the sort that prefers a frosty " + random_select(drinks_crappy_beers) + "?"
  
  wines = -> "True connoisseurs will enjoy the subtle flavors of this " + random_select(drinks_wines)
  
  special_drinks = 
    "bloody mary": "Hmmm, you sure you want that?"
    "4loko": "Are you ready to get SLAMMED?"
    "amf": "Say 'Adios', motherf*cker!"
    "beer": beers_on_tap
    "coors": "CHUG! CHUG! CHUG! CHUG!"
    "gin & tonic": "Here's a Gin & Tonic! Would you like some lime in that?"
    "keg": "Are you sure that isn't a bit much for one person?"
    "martini": "The 007 special, coming right up!"
    "mimosa": "It's always 11AM somewhere, right?"
    "natty": "Alright, one 'beer' coming right up..."
    "on me": "Hey everyone, this guy is buying you all a round!"
    "pop": "Are you sure you didn't mean a SODA?"
    "red-headed slut": "A fan of the gingers, are we?"
    "redbull & vodka": "Party it up in hurrrrrr"
    "sake bomb" : "HIROSHIMA, NAGASAKI, SAKE SAKE BOMB!"
    "sidecar": "One sidecar, coming right up!"
    "scotch": -> "/me pours a double of " + random_select(drinks_scotches)
    "soda": -> "Not drinking tonight? Here, have a " + random_select(drinks_sodas)
    "tom collins": "Alright, that'll be $7 please"
    "vodka": "One double of Stoli on the rocks, coming right up!"
    "white russian": "Yeah, but can you go drink-for-drink with The Dude?"
    "wine": wines
  
  special_drinks["beers"] = beers_on_tap
  special_drinks["wines"] = wines
  
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
      "Martini: shaken, not stirred."
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
      if args and args.trim() isnt ""
        selection =  "I'm all out of that, how about something else?"
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
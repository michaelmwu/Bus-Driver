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
  
  drinks_gins = [
    "Beefeater"
    "Bombay Sapphire"
    "Hendricks"
    "Magellan"
    "Tanqueray 10"
  ]
  
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
  
  drinks_tequilas = [
    "1800 Silver"
    "Don Eduardo Silver"
    "Jose Cuerve Gold Label"
    "Jose Cuervo Black Medallion"
    "Milagro Añejo"
    "Patron"
  ]
  
  drinks_vodkas = [
    "Absolut Orange"
    "Belvedere"
    "Grey Goose La Poire"
    "Ketel One"
    "Smirnoff"
    "Stoli"
    "Stoli Elit"
    "Three Olives"
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
  
  all_drinks = [
    drinks_beers
    drinks_crappy_beers
    drinks_gins
    drinks_scotches
    drinks_sodas
    drinks_tequilas
    drinks_vodkas
    drinks_wines
  ]
  all_drinks = _un.flatten(all_drinks)
  lc_all_drinks = _un.map(all_drinks, function (str)-> str.toLowerCase())
  
  n_beers = drinks_beers.length
  beers_on_tap = ->
    i = r.rand(n_beers)
    j = r.rand(n_beers-1)
    k = (i + j) % n_beers
    "Tap specials are the " + drinks_beers[i] + " and the " + drinks_beers[k] + ", or are you the sort that prefers " + random_select(drinks_crappy_beers) + "?"
  
  wines = -> "True connoisseurs will enjoy the subtle flavors of this " + random_select(drinks_wines)
  
  special_drinks = 
    "7&7": "One Seven & Seven, coming right up!"
    "bloody mary": "You know how spicy I make these, right?"
    "4loko": "Are you ready to get SLAMMED?"
    "amf": "Say 'Adios', motherf*cker!"
    "bacon": "Tuesday nights we have free bacon at the bar!"
    "beer": beers_on_tap
    "coors": "CHUG! CHUG! CHUG! CHUG!"
    "gin": -> "Ahh, the classic drink of alcoholics. Here's a triple of " + random_select(drinks_gins) + "!"
    "gin & tonic": -> "Here's a " + random_select(drinks_gins) + " and Tonic! Would you like some lime in that?"
    "grey goose": "Only the finest for you, huh?"
    "irish car bomb": "Hey, the IRA might have some use for you!"
    "jager bomb": "Take what you can, and give nothing back!"
    "keg": "Are you sure that isn't a bit much for one person?"
    "lemonade": "Just like your mother used to make you!"
    "mai tai": "Drink enough of these and you might think you're a tiki"
    "martini": "The 007 special, coming right up!"
    "milk": "Hold up, lemme go check on the cow out back"
    "mimosa": "It's always 11AM somewhere, right?"
    "mojito": "Welcome to Miami!"
    "natty": "Alright, one 'beer' coming right up..."
    "on me": "Hey everyone, this guy is buying you all a round!"
    "peanuts": "/me slides over the complimentary peanuts"
    "pbr": "I've got this other beer here you've probably never heard of, why don't you try that instead?"
    "pop": "Are you sure you didn't mean a SODA?"
    "pretzels": "/me places complimentary pretzels on counter"
    "red-headed slut": "A fan of the gingers, are we?"
    "redbull": "Redbull gives you wiiiiiiiiiiings"
    "redbull & vodka": "Party it up in hurrrrrr!"
    "rum": "You've been here for hours...guess why the rum is gone?"
    "rum & coke": "You look troubled, do you want me to make it a double?"
    "rum runner": "On vacation, or just pretending to be?"
    "sake bomb" : "HIROSHIMA, NAGASAKI, SAKE SAKE BOMB!"
    "shitty beer": -> "One frosty " + random_select(drinks_crappy_beers) + " coming right up!"
    "sidecar": "One sidecar, coming right up!"
    "screwdriver": -> "One " + random_select(drinks_vodkas) + " and OJ coming at you!"
    "scotch": -> "/me pours a double of " + random_select(drinks_scotches) + ", neat"
    "soda": -> "Not drinking tonight? Have a " + random_select(drinks_sodas) + "!"
    "tequila": -> "Tequila will make your clothes fall off, so here's a shot of " + random_select(drinks_tequilas) + "!"
    "tequila sunrise": "One tequila sunrise, coming right up!"
    "tom collins": "Alright, that'll be $7 please"
    "vodka": -> "One double of " + random_select(drinks_vodkas) + " on the rocks, coming right up!"
    "vodka tonic": -> "A " + random_select(drinks_vodkas) + " and tonic, coming right up!"
    "white russian": "Yeah, but can you go drink-for-drink with The Dude?"
    "wine": wines
  
  special_drinks["beers"] = beers_on_tap
  special_drinks["wines"] = wines
  special_drinks["redbull vodka"] = "Party it up in hurrrrrr!"
  
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
    
    lcDrink = args.trim().toLowerCase()
    
    selection = null
    
    if lcDrink of special_drinks
      selection = special_drinks[lcDrink]
      if typeof selection is "object"
        selection = random_select(selection)
    else
      if lcDrink and lcDrink isnt ""
        index = _un.indexOf(lc_all_drinks,lcDrink)
        if index < 0
          selection =  "I'm all out of that, how about something else?"
        else
          selection = "One " + all_drinks[index] + ", coming right up!"
      else
        selection = random_select(msgs)
    
    if typeof selection is "function"
      selection = selection()
    
    bot.speak selection
    
    bot.vote "up"
  
  cmd_toast = (user,args) ->
    toasts = [
      "Here's to you, here's to me: friends forever we shall be. If we ever disagree, F*CK YOU, here's to me!"
      "TO BILL BRASKY!"
      "To War, Women, and Witticism: May you always know when to pull out!"
      "May the best of your past be the worst of your future!"
      "Skål!"
      "To the nights we can't remember, with the friends we'll never forget!"
      "To our wives we love and our girlfriends we adore - may they never meet!"
      "Champagne for our real frinds, real pain for our sham friends!"
      "May the road rise up to meet you, may the wind always be at your back, and may the rain fall soft upon your fields"
      "May Those that love us love us, may those that don't love us, may the Lord turn their hearts. And if he can't turn their hearts may he turn their ankles...so we know them by their limping"
      "Blindness to our enemies!"
      "To infinity, and beyond!"
      "Here's to being single, seeing double, and seeing triple!"
      "To good times making bad decisions!"
      "Here's to the ships and women of our land: may the former be well-rigged, and the latter well-manned!"
      "May you be in heaven for half an hour before the devil knows you're dead!"
      "May all the ups and downs in life happen between the sheets!"
      "My friends are of the best kind: loyal, willing, and able. Now let's get to drinking, glasses off the table!"
      "Start your livers...get set...go!"
      "Here's to #{user.name}: may he live respected and die regretted!"
    ]
    bot.speak random_select(toasts)
    bot.vote "up"
  
  # Match regexes
  commands = [
    {cmd: /^\/drinks?$/, fn: cmd_drinks, help: "drinks"}
    {cmd: /^\/toasts?$/, fn: cmd_toast, help: "toast!"}
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
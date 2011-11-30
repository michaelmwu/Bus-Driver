Bot = require 'ttapi'
irc = require 'irc'
_ = require 'underscore'
util = require 'util'
r = require 'mersenne'
readline = require 'readline'

Db = require('mongodb').Db
Connection = require('mongodb').Connection
Server = require('mongodb').Server
  
db = new Db 'Bus-Bartender', new Server '127.0.0.1', 27017, {}
db.open (err, _db)->
	db = _db


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
  tabs = {}
  
  plural = (count) ->
    if count == 1
      's'
    else
      ''
  
  random_select = (list) ->
    list[r.rand(list.length)]
  
  norm = (name) ->
    name.trim().toLowerCase()
  
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
    "Stone Arrogant Basterd"
    "Stone Leviation Pale Ale"
    "Stone Ruination"
    "Young's Double Chocolate Stout"
  ]
  
  
  drinks_crappy_beers = [
    "Bud Light"
    "Budweiser"
    "Coors"
    "Coors Light"
    "Corona"
    "Dos Equis"
    "Keystone"
    "Keystone Ice"
    "Keystone Light"
    "Miller"
    "Miller Lite"
    "Natural"
    "Natural Ice"
    "Natural Light"
    "Rolling Rock"
  ]
  
  drinks_gins = [
    "Beefeater"
    "Bombay Sapphire"
    "Hendricks"
    "Magellan"
    "New Amsterdam"
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
    "Coke"
    "Coca-Cola"
    "Diet Coke"
    "Dr. Pepper"
    "Fanta"
    "Ginger Ale"
    "Mountain Dew"
    "Pepsi"
    "Root Beer"
    "Sierra Mist"
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
    "Absolut"
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
    "Heitz Cab Martha's '06"
    "Chardonnay"
    "Cabernet Sauvignon"
    "Franzia"
    "Pinot Noir"
    "Port"
    "Sauvignon Blanc"
    "Syrah"
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
  all_drinks = _.flatten(all_drinks)
  lc_all_drinks = _.map(all_drinks, (str)-> str.toLowerCase())
  
  n_beers = drinks_beers.length
  beers_on_tap = ->
    i = r.rand(n_beers)
    j = r.rand(n_beers-2)
    k = (i + j + 1) % n_beers
    "Tap specials are the " + drinks_beers[i] + " and the " + drinks_beers[k] + ", or are you the sort that prefers " + random_select(drinks_crappy_beers) + "?"
  
  cinnabuns = [
    "I could eat you for a lifetime"
    "You are my favorite pastry"
    "Your favorite pastry?"
    "You are, a Cinnabon, I could eat you forever"
    "Icing, cinnamon, I could eat you forever"
    "You are, a Cinnabon, a microwave treasure"
    "CH-CH-CH-CH-CH-CHOP THE STEAK"
    "d-_-b, get outta here"
  ]
  
  foods = 
    "": "What would you like to eat?"
    "bacon": "Tuesday nights we have free bacon at the bar!"
    "burger": "29 cents at McDonalds! Baby!"
    "cereal": "I think Mikey likes it!"
    "cinnabon": -> random_select(cinnabuns)
    "cinnabons": -> random_select(cinnabuns)
    "cinnabun": -> random_select(cinnabuns)
    "cinnabuns": -> random_select(cinnabuns)
    "cheeseburger": "39 cents at McDonalds! Baby!"
    "chips": "/me slides over the chips"
    "chocolate": "Once you go dark, you never go back!"
    "churro": "Por supuesto, amigo!"
    "eggo": "Leggo my eggo!"
    "eggo waffles": "Leggo my eggo!"
    "eggs": "Fertilized or unfertilized?"
    "fish sticks": "What are you, some kind of gay fish?"
    "fish taco": "Only with the finest, freshest fish!"
    "fish tacos": "Only with the finest, freshest fish!"
    "grilled cheese": "Let me fire up the griddle"
    "hamburger": "29 cents at McDonalds! Baby!"
    "ice cream": "What's your flavor?"
    "muffins": "Did you hear the joke about the talking muffins?"
    "nachos": "It's not yo cheese!"
    "pancakes": "Stacks and stacks!"
    "peanuts": "/me slides over the complimentary peanuts"
    "pho": "You like that cock sauce, don't you?"
    "pie": "Warm as apple pie..."
    "pizza": "Bringing the best of NY to a bus near you!"
    "poop": "Chocolate or double chocolate flavored?"
    "pretzels": "/me places complimentary pretzels on counter"
    "ramen": "Here's a packet, I'll fire up the water heater"
    "sammich": "No, YOU make me a sammich!"
    "sandwich": "Wicked wich of the beach?"
    "sausage": "Mmm sausage"
    "shit": "Keep that up and I'll call over the bouncer"
    "steak": -> "Personally, I prefer you run a cow by me and just let me go at it with a fork"
    "taco": "Hot sauce is on the counter"
    "tacos": "Hot sauce is on the counter"
    "turkey": "The tryptophan is making you verrrry sleepy"
  
  special_drinks = 
    "151": "Dude, are you that guy that does the firebreathing thing?"
    "4loko": "Are you ready to get SLAMMED?"
    "7&7": "One Seven & Seven, coming right up!"
    "amf": "Say 'Adios', motherf*cker!"
    "apple juice": "Let me get a sippy cup"
    "arnold palmer": "Half & half!"
    "beer": beers_on_tap
    "blood": "Vampires not allowed! Especially not the sparkly ones"
    "bloody mary": "You know how spicy I make these, right?"
    "boba": "Tap-X is open down the street"
    "body shot": "Hold up, have you even asked .Mnml_Pixels yet?"
    "body shots": "Hold up, have you even asked .Mnml_Pixels yet?"
    "box wine": (user)-> "#{user.name} can play Slap Bag like a BOSS!"
    "bubble tea": "Tap-X is just down the street"
    "brooklyn lager": "GalGal can stop telling me to add this to our menu now!"
    "cape cod": "Is it that time of the month?"
    "coffee": "Here's a cup of Joe to perk you up"
    "cough syrup": "Cough syrup is the best medicine!"
    "cum": "I'd stop by the men's bathroom for that"
    "everclear": "This stuff isn't usually taken in shot form, but I guess if you're that much of an alcoholic..."
    "flaming doctor pepper": "Remember to blow it out!"
    "franzia": (user)-> "#{user.name} can play Slap Bag like a BOSS!"
    "gin": -> "Ahh, the classic drink of alcoholics. Here's a triple of " + random_select(drinks_gins) + "!"
    "gin & tonic": -> "Here's a " + random_select(drinks_gins) + " and Tonic! Would you like some lime in that?"
    "grey goose": "Only the finest for you, huh?"
    "h2o":"Dihydrogen monoxide kills!"
    "irish car bomb": (user) -> "Hey #{user.name} if you like those, the IRA might have some use for you!"
    "jager bomb": "Take what you can, and give nothing back!"
    "jello shot": "What flavor would you like?"
    "jello shots": "What flavor would you like?"
    "keg": "Are you sure that isn't a bit much for one person?"
    "lean": "Got a cough?"
    "lemonade": "Just like your mother used to make you!"
    "mai tai": "Drink enough of these and you might think you're a tiki"
    "martini": "The 007 special, coming right up!"
    "milk": "Hold up, lemme go check on the cows in the undercarriage"
    "milkshake": "Our milkshake brings all the boys to the yard!"
    "mimosa": "It's always 11AM somewhere, right?"
    "monster": "Unleash the beast!"
    "moonshine": "I'll scoop some out of the bathtub"
    "moscow mule": "Only with the finest ginger beer"
    "mojito": "Next stop, Havana!"
    "natty": "Alright, one 'beer' coming right up..."
    "on me": (user) -> "Everyone order up, this round's on #{user.name}!"
    "piss": (user) -> "Time for some water sports!"
    "oj": "Let me get you a kiddy straw"
    "orange juice": "Want me to get a sippy cup?"
    "own piss": (user) -> "#{user.name}: Goes to party with a full bar, drinks own piss"
    "pabst blue ribbon": "I've got this other beer here you've probably never heard of, why don't you try that instead?"
    "pbr": "I've got this other beer here you've probably never heard of, why don't you try that instead?"
    "pmt": "Tap-X is open down the street"
    "pop": "Are you sure you didn't mean a SODA?"
    "purple drank": "Here's some of that purple drank"
    "red-headed slut": "A fan of the gingers, are we?"
    "redbull": "Redbull gives you WIIIIIIIINGS"
    "redbull & vodka": "Party it up in hurrrrrr!"
    "robitussium": "Got a cough?"
    "roofie": "What kind of establishment do you think this is? Our drinks are 99.9% roofie free!"
    "rum": "You've been here for hours...guess why the rum is gone?"
    "rum & coke": "That's a troubled look you're giving me, do you want me to make it a double?"
    "rum runner": "On vacation, or just pretending to be?"
    "sake" : "HIROSHIMA, NAGASAKI, SAKE SAKE BOMB!"
    "sake bomb" : "HIROSHIMA, NAGASAKI, SAKE SAKE BOMB!"
    "sex on the beach": "If you're under 18, I could just dry-hump you on the beach..."
    "sexy sundae": (user)-> "'Sexy' and '#{user.name}' never belong together, sorry!"
    "sizzurp": "Here's some of that purple drank"
    "soup": "NO SOUP FOR YOU"
    "shitty beer": -> "One frosty " + random_select(drinks_crappy_beers) + " coming right up!"
    "sidecar": "One sidecar, coming right up!"
    "screwdriver": -> "One " + random_select(drinks_vodkas) + " and OJ coming at you!"
    "scotch": -> "/me pours a double of " + random_select(drinks_scotches) + ", neat"
    "soda": -> "Not drinking tonight? Have a " + random_select(drinks_sodas) + "!"
    "tequila": -> "Tequila will make your clothes fall off, so here's a shot of " + random_select(drinks_tequilas) + "!"
    "tequila sunrise": "One tequila sunrise, coming right up!"
    "texas tea": "Got a cough?"
    "tom collins": (user)-> "#{user.name}, do you want that added to your tab?"
    "toilet water": "It's free in the bathroom"
    "urine": "Let's start the water works!"
    "v8": "Veggie goodness!"
    "vodka": -> "One double of " + random_select(drinks_vodkas) + " on the rocks, coming right up!"
    "vodka tonic": -> "A " + random_select(drinks_vodkas) + " and Tonic, coming right up!"
    "water":"ಠ_ಠ  Hey, isn't this the PARTY bus?"
    "white russian": "Yeah, but can you go drink-for-drink with The Dude?"
    "whiskey": "Coming right up!"
    "wine": -> "True connoisseurs will enjoy the subtle flavors of this " + random_select(drinks_wines)
  
  special_drinks["beers"] = beers_on_tap
  special_drinks["redbull vodka"] = "Party it up in hurrrrrr!"
  
  bot.on "registered", (data) ->
    if data.user[0].userid is selfId
      # We just joined, initialize
      db.collection 'tabs', (err, col)->
        criteria = 
          removed: false
        col.find criteria, (err, cursor)->
          cursor.each (err,doc)->
            if doc isnt null
              tabs[doc.tabUserInfo.userid] = doc.owed
              
      # Add other collections like hearts, etc
      
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
      "#{user.name}, you might need to find your own ride home after this..."
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
      change_tab(user,8)
    else
      if lcDrink and lcDrink isnt ""
        index = _.indexOf(lc_all_drinks,lcDrink)
        if index < 0
          selection =  "I'm all out of that, how about something else?"
          util.puts "Unknown drink #{args}"
        else
          selection = "One " + all_drinks[index] + ", coming right up!"
          change_tab(user,6)
      else
        selection = random_select(msgs)
        change_tab(user,4)
    
    if typeof selection is "function"
      selection = selection(user)
    
    bot.speak selection
    
  change_tab = (user,amount) ->
    uid = user.userid
    if uid not in _.keys tabs
      tabs[uid] = amount
      db.collection 'tabs', (err,col) ->
        col.insert
          tabUserInfo: user
          owed: tabs[uid]
          removed: false
    else
      tabs[uid] = tabs[uid] + amount
      db.collection 'tabs', (err,col) ->
        criteria = 
          'tabUserInfo.userid': uid
        modification = 
          '$set':
            owed: tabs[uid]
        col.update criteria, modification, true
    
  cmd_tab = (user) ->
    uid = user.userid
    if uid not in _.keys tabs
      msg =  "#{user.name} has yet to order anything!"
    else
      msg = "#{user.name} owes me $" + tabs[uid] + " and better pay up soon!"
    bot.speak msg
  
  cmd_toast = (user,args) ->
    toasts = [
      "Here's to you, here's to me: friends forever we shall be. If we ever disagree, F*CK YOU, here's to me!"
      "TO BILL BRASKY!"
      "To War, Women, and Witticism: May you always know when to pull out!"
      "May the best of your past be the worst of your future!"
      "Skål!"
      "To the nights we can't remember with the friends we'll never forget!"
      "To our wives we love and our girlfriends we adore - may they never meet!"
      "Champagne for our real friends, real pain for our sham friends!"
      "May the road rise up to meet you, may the wind always be at your back, and may the rain fall soft upon your fields"
      "May Those that love us love us, may those that don't love us, may the Lord turn their hearts. And if he can't turn their hearts may he turn their ankles...so we know them by their limping"
      "Blindness to our enemies!"
      "To infinity, and beyond!"
      "Here's to being single, seeing double, and sleeping triple!"
      "To good times making bad decisions!"
      "Here's to the ships and women of our land: may the former be well-rigged, and the latter well-manned!"
      "May you be in heaven for half an hour before the devil knows you're dead!"
      "May all your ups and downs in life happen between the sheets!"
      "My friends are of the best kind: loyal, willing, and able. Now let's get to drinking, glasses off the table!"
      "Start your livers...get set...go!"
      "Here's to #{user.name}: may he live respected and die regretted!"
      "To alcohol! The cause of, and solution to all of life's problems!"
      "To good times making bad decisions!"
    ]
    change_tab(user,-3)
    bot.speak random_select(toasts)
    
  
  cmd_eat = (user,args) ->
    lcFood = args.trim().toLowerCase()
    selection = null
    
    if lcFood of foods
      selection = foods[lcFood]
      change_tab(user,5)
    else
      selection = "We don't serve your kind here!"
      util.puts "Unknown food #{args}"
    
    if typeof selection is "function"
      selection = selection(user)
    
    bot.speak selection
    
  
  cmd_burn = (user,args) ->    
    lcBurn = args.trim().toLowerCase()
    selection = null
    bot.roomInfo (data) ->
      name = norm(args)
      
      if name isnt ""
        # Initialize users
        if user = _.find(data.users, (user) -> norm(user.name) is norm(args))
            
            burns = [
              "#{user.name}, you're out of your game. I heard you retired, and they named second place after you. BURRRNNNNNN!"
              "By the way #{user.name}, you still owe me that rent check because of all that time you spent living in my shadow. BURRRNNNNNN!"
              "Hey I have a question about your hair, #{user.name}. When exactly did Brillo Pads start making toupees? BURRRNNNNNN!"
            ]
            
            selection = random_select(burns)
        else
          selection = "#{name} isn't in this room!"
      else
        selection = "Who got pwned?"
    
      bot.speak selection
    
    
  
  # Match regexes
  commands = [
    {cmd: /^\/drinks?$/, fn: cmd_drinks, help: "drinks"}
    {cmd: /^\/tab$/, fn: cmd_tab, help: "tab announcer"}
    {cmd: /^\/toasts?$/, fn: cmd_toast, help: "toast!"}
    {cmd: /^\/eats?$/, fn: cmd_eat, help: "drinks"}
    {cmd: /^\/burn$/, fn: cmd_burn, help: "drinks"}
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
    
    resolved_cmd = _.detect(commands, cmd_matches)
    
    if resolved_cmd
        resolved_cmd.fn(user, args)
  
exports.bartender = bartender

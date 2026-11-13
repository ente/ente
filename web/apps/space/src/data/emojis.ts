export interface SpaceEmoji {
    emoji: string;
    name: string;
    keywords: string;
    skinTone: boolean;
}

interface SpaceEmojiCategory {
    name: string;
    emojis: SpaceEmoji[];
}

const category = (name: string, entries: string): SpaceEmojiCategory => ({
    name,
    emojis: entries
        .trim()
        .split("\n")
        .map((entry) => {
            const [emoji = "", label = "", keywords = ""] = entry.split("|");
            return {
                emoji,
                name: label.replace("*", ""),
                keywords,
                skinTone: label.endsWith("*"),
            };
        }),
});

const regionNames = new Intl.DisplayNames(["en"], { type: "region" });
const flagRegions =
    "AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW EU UN";

const spaceEmojiCategories = [
    category(
        "Faces",
        `
😀|Big smile|happy grin
😃|Happy face|smile joy
😄|Beaming smile|happy laugh
😁|Grinning eyes|happy teeth
😆|Laughing|haha lol
😅|Nervous laugh|sweat relief
😂|Tears of laughter|joy funny lol haha
🤣|Rolling with laughter|rofl funny lol
😊|Warm smile|blush happy
🙂|Little smile|happy
🙃|Upside down|sarcasm silly
😉|Wink|playful
😌|Relieved|calm peace
😍|Heart eyes|love crush
🥰|Feeling loved|hearts love
😘|Blowing a kiss|love
😗|Kiss|love
😙|Smiling kiss|love
😚|Blushing kiss|love
😋|Yummy|delicious food
😛|Tongue out|silly
😜|Winking tongue|silly playful
🤪|Goofy|crazy silly
😝|Squinting tongue|silly
🤑|Money face|rich cash
🤗|Hug|thanks cuddle
🤭|Hand over mouth|oops giggle
🫢|Surprised gasp|shock
🫣|Peeking|shy scared
🤫|Shush|quiet secret
🤔|Thinking|hmm question
🫡|Salute|respect yes
🤐|Sealed lips|secret quiet
🤨|Raised eyebrow|skeptical
😐|Neutral|blank
😑|Unimpressed|expressionless
😶|Speechless|silent
🫥|Invisible|awkward
😏|Smirk|sly
😒|Not amused|annoyed
🙄|Eye roll|whatever
😬|Awkward grin|oops
😮‍💨|Sigh|relief exhausted
🤥|Lying|pinocchio
😔|Downhearted|sad
😪|Sleepy|tired
🤤|Drooling|hungry
😴|Sleeping|tired snooze
😷|Face mask|sick
🤒|Fever|sick ill
🤕|Injured|hurt bandage
🤢|Nauseous|sick gross
🤮|Vomiting|sick gross
🤧|Sneezing|cold sick
🥵|Too hot|sweating
🥶|Freezing|cold
🥴|Woozy|dizzy
😵|Dizzy|shock
🤯|Mind blown|amazing wow
🤠|Cowboy|hat
🥳|Party face|celebrate birthday
🥸|Disguise|glasses mustache
😎|Cool|sunglasses
🤓|Nerd|glasses clever
🧐|Monocle|curious
😕|Confused|unsure
🫤|Unsure|uneasy
😟|Worried|concern
🙁|Frown|sad
☹️|Sad face|unhappy
😮|Surprised|wow oh
😯|Hushed|surprise
😲|Astonished|wow shock
😳|Flushed|embarrassed
🥺|Pleading|please puppy
🥹|Holding back tears|touched grateful
😦|Worried gasp|shock
😧|Anguished|worried
😨|Fearful|scared
😰|Anxious|sweat nervous
😥|Sad and relieved|disappointed
😢|Crying|sad tear
😭|Sobbing|cry sad
😱|Screaming|scared shock
😖|Frustrated|upset
😣|Struggling|persevere
😞|Disappointed|sad
😓|Cold sweat|stress
😩|Weary|tired
😫|Exhausted|tired
🥱|Yawning|bored sleepy
😤|Huffing|angry proud
😡|Angry|mad rage
😠|Annoyed|angry
🤬|Swearing|angry rage
😈|Cheeky devil|mischief
👿|Angry devil|mad
💀|Skull|dead dying laugh
☠️|Skull and bones|danger
💩|Poop|silly
🤡|Clown|silly joke
👻|Ghost|boo spooky
👽|Alien|space
🤖|Robot|technology
😺|Smiling cat|happy
😸|Grinning cat|happy
😹|Laughing cat|funny lol
😻|Heart eyes cat|love
😼|Smirking cat|sly
😽|Kissing cat|love
🙀|Shocked cat|surprise
😿|Crying cat|sad
😾|Angry cat|mad
🙈|See no evil|shy monkey
🙉|Hear no evil|monkey
🙊|Speak no evil|secret monkey
`,
    ),
    category(
        "People",
        `
👋|Wave*|hello goodbye hi
🤚|Raised back of hand*|stop
🖐️|Open hand*|five
✋|Raised hand*|stop high five
🖖|Vulcan salute*|live prosper
🫱|Hand right*|handshake
🫲|Hand left*|handshake
👌|Okay*|ok perfect
🤌|Pinched fingers*|chef kiss
🤏|Tiny amount*|small
✌️|Peace*|victory two
🤞|Crossed fingers*|luck hope
🫰|Finger heart*|love
🤟|Love you*|hand
🤘|Rock on*|metal
🤙|Call me*|hang loose
👈|Point left*|direction
👉|Point right*|direction
👆|Point up*|direction
👇|Point down*|direction
☝️|One moment*|up attention
🫵|You*|point
👍|Thumbs up*|yes good like approve
👎|Thumbs down*|no dislike
✊|Raised fist*|solidarity
👊|Fist bump*|punch
🤛|Left fist*|bump
🤜|Right fist*|bump
👏|Clapping*|bravo applause congratulations
🙌|Celebration hands*|hooray praise
🫶|Heart hands*|love
👐|Open hands*|welcome
🤲|Palms together*|hope
🤝|Handshake|deal agreement
🙏|Folded hands*|please thanks pray grateful
✍️|Writing*|note
💅|Nail polish*|beauty fancy
🤳|Selfie*|camera
💪|Strong arm*|strength flex workout
🦾|Mechanical arm|strength
🦵|Leg*|kick
🦶|Foot*|step
👂|Ear*|listen
👃|Nose*|smell
🧠|Brain|think smart
🫀|Anatomical heart|health
🦷|Tooth|dentist
👀|Eyes|look watching
👁️|Eye|watch
👅|Tongue|taste
👄|Lips|kiss
👶|Baby*|child
🧒|Child*|young
🧑|Person*|adult
👩|Woman*|adult
👨|Man*|adult
🧓|Older person*|elder
👵|Grandmother*|elder
👴|Grandfather*|elder
🙍|Frowning person*|sad
🙎|Pouting person*|angry
🙅|No gesture*|stop
🙆|Okay gesture*|yes
💁|Helping hand*|information
🙋|Hand raised*|question
🧏|Deaf person*|hearing
🙇|Bowing*|sorry respect
🤦|Facepalm*|oops disbelief
🤷|Shrug*|idk whatever
👮|Police officer*|law
🕵️|Detective*|mystery
💂|Guard*|royal
👷|Builder*|construction
🧑‍⚕️|Health worker*|doctor nurse
🧑‍🎓|Graduate*|student school
🧑‍🏫|Teacher*|school
🧑‍🍳|Cook*|chef food
🧑‍💻|Developer*|computer work coding
🧑‍🎨|Artist*|paint creative
🧑‍🚀|Astronaut*|space
👼|Angel*|innocent
🎅|Santa*|christmas
🦸|Superhero*|hero
🦹|Villain*|evil
🧙|Wizard*|magic
🧚|Fairy*|magic
🧛|Vampire*|halloween
🧜|Merperson*|sea
🧝|Elf*|fantasy
🧞|Genie|wish
🧟|Zombie|halloween
💃|Dancing woman*|party
🕺|Dancing man*|party
🚶|Walking*|stroll
🏃|Running*|exercise
🧘|Meditating*|calm yoga
🛌|In bed*|sleep
👨‍👩‍👧‍👦|Family|parents children
`,
    ),
    category(
        "Nature",
        `
🐶|Dog|puppy pet
🐱|Cat|kitten pet
🐭|Mouse|animal
🐹|Hamster|pet
🐰|Rabbit|bunny
🦊|Fox|animal
🐻|Bear|animal
🐼|Panda|bear
🐻‍❄️|Polar bear|snow
🐨|Koala|animal
🐯|Tiger|cat
🦁|Lion|cat
🐮|Cow|moo
🐷|Pig|oink
🐸|Frog|animal
🐵|Monkey|animal
🐔|Chicken|bird
🐧|Penguin|bird
🐦|Bird|tweet
🐤|Chick|baby bird
🦆|Duck|quack
🦅|Eagle|bird
🦉|Owl|bird wise
🦇|Bat|night
🐺|Wolf|howl
🐗|Boar|pig
🐴|Horse|pony
🦄|Unicorn|magic
🐝|Bee|honey
🦋|Butterfly|insect
🐌|Snail|slow
🐞|Ladybug|luck
🐜|Ant|insect
🕷️|Spider|web
🦂|Scorpion|animal
🐢|Turtle|slow
🐍|Snake|reptile
🦎|Lizard|reptile
🦖|Dinosaur|t rex
🐙|Octopus|sea
🦑|Squid|sea
🦀|Crab|sea
🐠|Tropical fish|sea
🐟|Fish|sea
🐬|Dolphin|sea
🐳|Whale|sea
🦈|Shark|sea
🐊|Crocodile|reptile
🐘|Elephant|animal
🦒|Giraffe|animal
🦓|Zebra|stripes
🦍|Gorilla|ape
🦧|Orangutan|ape
🐪|Camel|desert
🦙|Llama|animal
🦘|Kangaroo|animal
🦥|Sloth|slow
🦦|Otter|water
🦔|Hedgehog|animal
🐾|Paw prints|pet
🐉|Dragon|fantasy
🌵|Cactus|desert plant
🎄|Christmas tree|holiday
🌲|Evergreen|tree forest
🌳|Tree|forest
🌴|Palm tree|tropical beach
🌱|Seedling|growth plant
🌿|Herb|green plant
☘️|Shamrock|luck
🍀|Four leaf clover|luck
🍁|Maple leaf|autumn
🍂|Falling leaves|autumn
🍃|Leaf in wind|breeze
🍄|Mushroom|nature
🌹|Rose|flower love
🥀|Wilted flower|sad
🌷|Tulip|flower
🌸|Cherry blossom|flower spring
🌼|Blossom|flower
🌻|Sunflower|flower sun
🌺|Hibiscus|flower
💐|Bouquet|flowers thanks
🌍|Earth|world globe
🌎|Americas globe|world earth
🌏|Asia globe|world earth
🌙|Crescent moon|night
🌕|Full moon|night
⭐|Star|favorite
🌟|Glowing star|sparkle
✨|Sparkles|magic beautiful
☀️|Sun|bright sunny
🌤️|Partly sunny|weather
☁️|Cloud|weather
🌧️|Rain|weather
⛈️|Storm|thunder
🌈|Rainbow|color
❄️|Snowflake|winter cold
☃️|Snowman|winter
⚡|Lightning|energy fast
🔥|Fire|hot lit amazing
💧|Droplet|water
🌊|Wave|ocean water
`,
    ),
    category(
        "Food",
        `
🍎|Apple|fruit
🍏|Green apple|fruit
🍐|Pear|fruit
🍊|Orange|fruit
🍋|Lemon|fruit
🍌|Banana|fruit
🍉|Watermelon|fruit
🍇|Grapes|fruit
🍓|Strawberry|fruit
🫐|Blueberries|fruit
🍒|Cherries|fruit
🍑|Peach|fruit
🥭|Mango|fruit
🍍|Pineapple|fruit
🥥|Coconut|fruit
🥝|Kiwi|fruit
🍅|Tomato|vegetable
🥑|Avocado|food
🥦|Broccoli|vegetable
🥬|Leafy greens|salad
🥒|Cucumber|vegetable
🌶️|Chili|spicy pepper
🫑|Bell pepper|vegetable
🌽|Corn|vegetable
🥕|Carrot|vegetable
🧄|Garlic|food
🧅|Onion|food
🥔|Potato|vegetable
🍞|Bread|toast
🥐|Croissant|pastry
🥯|Bagel|bread
🧀|Cheese|food
🥚|Egg|breakfast
🍳|Fried egg|breakfast cooking
🥞|Pancakes|breakfast
🧇|Waffle|breakfast
🥓|Bacon|food
🍗|Chicken leg|food
🍔|Burger|food
🍟|Fries|food
🍕|Pizza|food
🌭|Hot dog|food
🥪|Sandwich|lunch
🌮|Taco|food
🌯|Burrito|food
🥗|Salad|healthy
🍝|Pasta|spaghetti
🍜|Noodles|ramen soup
🍲|Stew|soup
🍛|Curry rice|food
🍣|Sushi|food
🥟|Dumpling|food
🍚|Rice|food
🍙|Rice ball|food
🍿|Popcorn|movie
🧂|Salt|food
🍦|Ice cream cone|dessert
🍨|Ice cream|dessert
🍩|Doughnut|dessert
🍪|Cookie|dessert
🎂|Birthday cake|celebrate
🍰|Cake slice|dessert
🧁|Cupcake|dessert
🥧|Pie|dessert
🍫|Chocolate|sweet
🍬|Candy|sweet
🍭|Lollipop|sweet
🍯|Honey|sweet
🥛|Milk|drink
☕|Coffee|tea drink
🫖|Teapot|tea
🍵|Tea|drink
🧃|Juice|drink
🥤|Soft drink|soda
🧋|Bubble tea|boba drink
🍺|Beer|drink
🍻|Beer cheers|celebrate
🥂|Cheers|celebrate toast
🍷|Wine|drink
🍸|Cocktail|drink
🍹|Tropical drink|vacation
🍾|Champagne|celebrate
`,
    ),
    category(
        "Travel",
        `
🚗|Car|drive
🚕|Taxi|ride
🚌|Bus|transport
🚎|Trolleybus|transport
🏎️|Racing car|fast
🚓|Police car|transport
🚑|Ambulance|health
🚒|Fire engine|rescue
🚚|Delivery truck|transport
🚜|Tractor|farm
🛵|Scooter|ride
🏍️|Motorcycle|ride
🚲|Bicycle|cycle
🛴|Kick scooter|ride
🚂|Locomotive|train
🚆|Train|transport
🚇|Metro|subway
✈️|Airplane|flight vacation
🛫|Taking off|flight
🛬|Landing|flight
🚁|Helicopter|flight
🚀|Rocket|space launch
🛸|Flying saucer|ufo alien
⛵|Sailboat|sea
🚤|Speedboat|sea
🚢|Ship|cruise sea
⚓|Anchor|sea
🚦|Traffic light|road
🗺️|Map|travel
🧭|Compass|direction
⛰️|Mountain|hike
🏔️|Snowy mountain|hike
🌋|Volcano|lava
🏕️|Camping|tent
🏖️|Beach|vacation
🏜️|Desert|sand
🏝️|Island|vacation
🏠|Home|house
🏡|House and garden|home
🏢|Office|work
🏥|Hospital|health
🏫|School|education
🏰|Castle|royal
🗼|Tower|tokyo
🗽|Statue of liberty|new york
⛪|Church|building
🕌|Mosque|building
🛕|Temple|building
⛩️|Shrine|building
🌅|Sunrise|morning
🌄|Mountain sunrise|morning
🌇|Sunset|evening
🌃|City at night|stars
🌌|Galaxy|space stars
🌉|Bridge at night|city
🎡|Ferris wheel|fun fair
🎢|Roller coaster|fun
⛲|Fountain|water
⛺|Tent|camping
🧳|Luggage|travel
⌛|Hourglass|time waiting
⏰|Alarm clock|time
⌚|Watch|time
`,
    ),
    category(
        "Activities",
        `
⚽|Football|soccer sport
🏀|Basketball|sport
🏈|American football|sport
⚾|Baseball|sport
🎾|Tennis|sport
🏐|Volleyball|sport
🏉|Rugby|sport
🥏|Flying disc|frisbee
🎱|Pool|billiards
🏓|Table tennis|ping pong
🏸|Badminton|sport
🏏|Cricket|sport
🏒|Ice hockey|sport
🏑|Field hockey|sport
⛳|Golf|sport
🏹|Archery|bow arrow
🎣|Fishing|sport
🥊|Boxing glove|sport
🥋|Martial arts|sport
🎽|Running shirt|sport
🛹|Skateboard|sport
🛼|Roller skates|sport
⛸️|Ice skate|sport
🎿|Skiing|snow sport
🏂|Snowboarder*|snow sport
🏄|Surfing*|wave sport
🏊|Swimming*|water sport
🚴|Cycling*|bike sport
🧗|Climbing*|sport
🏆|Trophy|winner award
🥇|Gold medal|first winner
🥈|Silver medal|second
🥉|Bronze medal|third
🏅|Medal|award
🎖️|Military medal|award
🎯|Bullseye|target goal
🎮|Video game|play gaming
🕹️|Joystick|gaming
🎲|Dice|luck game
🧩|Puzzle|piece
♟️|Chess pawn|game
🎭|Theater|drama acting
🎨|Paint palette|art creative
🧵|Thread|sewing
🧶|Yarn|knitting
🎼|Music score|song
🎵|Music note|song
🎶|Music notes|song
🎤|Microphone|sing karaoke
🎧|Headphones|music listen
🎷|Saxophone|music
🎸|Guitar|music rock
🎹|Piano|music
🎺|Trumpet|music
🎻|Violin|music
🥁|Drum|music
🎬|Movie clapper|film
🎪|Circus|show
🎟️|Tickets|event
🎉|Party popper|congratulations celebrate tada
🎊|Confetti|celebrate
🎈|Balloon|birthday party
🎁|Gift|present birthday
🎀|Ribbon|gift
🎆|Fireworks|celebrate
🎇|Sparkler|celebrate
🪔|Oil lamp|diwali
🎃|Pumpkin|halloween
`,
    ),
    category(
        "Objects",
        `
📱|Phone|mobile
☎️|Telephone|call
💻|Laptop|computer work
🖥️|Desktop computer|work
⌨️|Keyboard|computer
🖱️|Computer mouse|click
🖨️|Printer|paper
📷|Camera|photo
📸|Taking a photo|camera flash
📹|Video camera|film
🎥|Movie camera|film
📺|Television|watch
📻|Radio|music
💡|Light bulb|idea
🔦|Flashlight|torch light
🕯️|Candle|light
🔋|Battery|energy
🔌|Plug|power
💸|Flying money|spending
💰|Money bag|rich cash
💳|Credit card|pay
💎|Gem|diamond
⚖️|Scales|balance justice
🔧|Wrench|tool fix
🔨|Hammer|tool
🛠️|Tools|fix build
⚙️|Gear|settings
🧲|Magnet|attract
🧪|Test tube|science
🔬|Microscope|science
🔭|Telescope|space
💊|Pill|medicine
💉|Syringe|medicine
🩹|Bandage|healing
🩺|Stethoscope|doctor
🛏️|Bed|sleep
🛋️|Sofa|relax
🚪|Door|entry
🪑|Chair|seat
🪟|Window|home
🧹|Broom|clean
🧼|Soap|clean
🧽|Sponge|clean
🧴|Lotion|care
🪥|Toothbrush|clean
🧻|Paper roll|tissue
🧺|Basket|laundry
🧸|Teddy bear|cuddle toy
🪁|Kite|play
🪄|Magic wand|wish
🪩|Disco ball|dance party
📦|Package|delivery box
✉️|Envelope|mail
💌|Love letter|mail
📩|Incoming mail|email
📚|Books|read study
📖|Open book|read
📓|Notebook|notes
📄|Page|document
📰|Newspaper|news
📝|Memo|write notes
✏️|Pencil|write
🖊️|Pen|write
🖌️|Paintbrush|art
📅|Calendar|date
📆|Tear off calendar|date
📈|Chart rising|growth
📉|Chart falling|decline
📊|Bar chart|data
📌|Pin|save
📍|Location pin|place
📎|Paperclip|attachment
✂️|Scissors|cut
🔒|Locked|private secure
🔓|Unlocked|open
🔑|Key|password
🗝️|Old key|unlock
🔔|Bell|notification
🔕|Muted bell|quiet
📢|Loudspeaker|announcement
📣|Megaphone|cheer
🔍|Magnifier|search
`,
    ),
    category(
        "Symbols",
        `
❤️|Red heart|love like
🧡|Orange heart|love
💛|Yellow heart|love friendship
💚|Green heart|love
💙|Blue heart|love
💜|Purple heart|love
🖤|Black heart|love
🤍|White heart|love
🤎|Brown heart|love
🩷|Pink heart|love
🩵|Light blue heart|love
🩶|Gray heart|love
💔|Broken heart|sad heartbreak
❤️‍🔥|Heart on fire|passion love
❤️‍🩹|Healing heart|care recovery
💕|Two hearts|love
💞|Spinning hearts|love
💓|Beating heart|love
💗|Growing heart|love
💖|Sparkling heart|love
💘|Heart and arrow|love cupid
💝|Heart gift|love
💟|Heart decoration|love
❣️|Heart exclamation|love
💋|Kiss mark|love
💯|Hundred|perfect agree
💢|Anger symbol|mad
💥|Boom|explosion impact
💫|Dizzy stars|sparkle
💦|Sweat drops|water
💨|Dash|fast wind
🕳️|Hole|empty
💬|Speech bubble|chat message
💭|Thought bubble|thinking
🗯️|Angry bubble|shout
💤|Sleep symbol|zzz tired
✅|Check mark|yes done correct
☑️|Checked box|done
✔️|Check|yes correct
❌|Cross|no wrong
❎|Crossed box|no
➕|Plus|add
➖|Minus|remove
✖️|Multiply|times
➗|Divide|math
♾️|Infinity|forever
❓|Question|what
❔|Light question|what
❗|Exclamation|attention
❕|Light exclamation|attention
‼️|Double exclamation|wow
⁉️|Question and exclamation|what wow
⚠️|Warning|caution
⛔|No entry|stop
🚫|Prohibited|no
🔞|Adults only|eighteen
♻️|Recycle|green environment
⚜️|Fleur de lis|symbol
🔱|Trident|symbol
⚕️|Medical symbol|health
☮️|Peace symbol|peace
☯️|Yin yang|balance
☸️|Dharma wheel|religion
✡️|Star of David|religion
✝️|Cross symbol|religion
☪️|Crescent and star|religion
🕉️|Om|religion
🪯|Khanda|religion
🔴|Red circle|color
🟠|Orange circle|color
🟡|Yellow circle|color
🟢|Green circle|color
🔵|Blue circle|color
🟣|Purple circle|color
⚫|Black circle|color
⚪|White circle|color
🟤|Brown circle|color
🟥|Red square|color
🟧|Orange square|color
🟨|Yellow square|color
🟩|Green square|color
🟦|Blue square|color
🟪|Purple square|color
⬛|Black square|color
⬜|White square|color
🟫|Brown square|color
🔶|Orange diamond|shape
🔷|Blue diamond|shape
🔺|Up triangle|shape
🔻|Down triangle|shape
⬆️|Up arrow|direction
⬇️|Down arrow|direction
⬅️|Left arrow|direction
➡️|Right arrow|direction
↗️|Up right arrow|direction
↘️|Down right arrow|direction
↙️|Down left arrow|direction
↖️|Up left arrow|direction
🔄|Repeat|refresh
🔙|Back|arrow
🔜|Soon|arrow
🔝|Top|arrow
🆕|New|fresh
🆒|Cool button|nice
🆗|OK button|yes
🆘|SOS|help
🆙|Up button|level
0️⃣|Zero|number
1️⃣|One|number
2️⃣|Two|number
3️⃣|Three|number
4️⃣|Four|number
5️⃣|Five|number
6️⃣|Six|number
7️⃣|Seven|number
8️⃣|Eight|number
9️⃣|Nine|number
🔟|Ten|number
#️⃣|Hash|number key
*️⃣|Asterisk|key
🏁|Finish flag|racing
🚩|Red flag|warning
🏳️|White flag|surrender
🏴|Black flag|flag
🏳️‍🌈|Rainbow flag|pride
🏳️‍⚧️|Transgender flag|pride
🏴‍☠️|Pirate flag|skull
`,
    ),
    {
        name: "Flags",
        emojis: flagRegions
            .split(" ")
            .map((region) => ({
                emoji: String.fromCodePoint(
                    region.charCodeAt(0) + 127397,
                    region.charCodeAt(1) + 127397,
                ),
                name: regionNames.of(region)!,
                keywords: `flag ${region.toLowerCase()}`,
                skinTone: false,
            })),
    },
];

export const spaceEmojis = spaceEmojiCategories.flatMap(({ emojis }) => emojis);

export const emojiWithSkinTone = (entry: SpaceEmoji, tone: string) => {
    if (!tone || !entry.skinTone) return entry.emoji;
    const first = String.fromCodePoint(entry.emoji.codePointAt(0)!);
    return `${first}${tone}${entry.emoji.slice(first.length).replace("\uFE0F", "")}`;
};

export const quickReactionEmojis = (selected?: string) => {
    const tone = selected?.match(/[\u{1F3FB}-\u{1F3FF}]/u)?.[0] ?? "";
    const emojis = ["❤️", "😂", "😮", "😢", "🙏", "👍"].map((emoji) =>
        emojiWithSkinTone(
            spaceEmojis.find((entry) => entry.emoji == emoji)!,
            tone,
        ),
    );
    return selected && !emojis.includes(selected)
        ? [...emojis.slice(0, 5), selected]
        : emojis;
};

export const searchEmojis = (entries: SpaceEmoji[], query: string) => {
    const normalized = query
        .trim()
        .toLowerCase()
        .replace(/[\u{1F3FB}-\u{1F3FF}]/gu, "");
    const terms = normalized.split(/\s+/u);
    return entries.filter((entry) =>
        terms.every((term) =>
            `${entry.emoji} ${entry.name} ${entry.keywords}`
                .toLowerCase()
                .includes(term),
        ),
    );
};

export const emojiName = (emoji: string) =>
    spaceEmojis.find(
        (entry) =>
            entry.emoji.replace(/\uFE0F/gu, "") ==
            emoji
                .replace(/[\u{1F3FB}-\u{1F3FF}]/gu, "")
                .replace(/\uFE0F/gu, ""),
    )?.name ?? "Emoji";

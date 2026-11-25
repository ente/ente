import "package:intl/intl.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/copy/rewind_copy.dart";

final _decimal = NumberFormat.decimalPattern("en_US");

const _months = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];

const _weekdays = [
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
  "Sunday",
];

String _ordinal(int day) {
  final teen = day % 100 >= 11 && day % 100 <= 13;
  final suffix = teen
      ? "th"
      : switch (day % 10) {
          1 => "st",
          2 => "nd",
          3 => "rd",
          _ => "th",
        };
  return "$day$suffix";
}

class EnglishRewindCopy extends RewindCopy {
  const EnglishRewindCopy();

  String _counted(int value, String one, String many) =>
      "${number(value)} ${value == 1 ? one : many}";

  @override
  String number(int value) => _decimal.format(value);

  @override
  String photoTally(String number, int count) => "$number ${photoUnit(count)}";

  @override
  String photoUnit(int count) => count == 1 ? "photo" : "photos";

  @override
  String shortDate(int day, int month, int year) =>
      "$day ${_months[month - 1].substring(0, 3).toUpperCase()} $year";

  @override
  String monthBanner(int month) => _months[month - 1].toUpperCase();

  @override
  String monthName(int month) => _months[month - 1];

  @override
  String get close => "Close";

  @override
  String get playMusic => "Play music";

  @override
  String get muteMusic => "Mute music";

  @override
  String get share => "Share";

  @override
  String get shareVideo => "Share video";

  @override
  String get nextCard => "Next card";

  @override
  String pageOf(int page, int count) => "Page $page of $count";

  @override
  String get dismiss => "Dismiss";

  @override
  String get watch => "Watch";

  @override
  String get watchAgain => "Watch again";

  @override
  String get resume => "Continue";

  @override
  String get newStatus => "New";

  @override
  String get newSticker => "NEW";

  @override
  String progress(int page, int count) => "$page of $count";

  @override
  String get readyTitle => "Your ${RewindEdition.year} Rewind is ready";

  @override
  String get readyBody => "Your year in photos. Ready when you are.";

  @override
  String get newCardsTitle => "Your ${RewindEdition.year} Rewind has new cards";

  @override
  String get newCardsBody => "Open it again to see what's new.";

  @override
  RewindLines get coverTagline =>
      (you: "YOUR YEAR IN PHOTOS", me: "MY YEAR IN PHOTOS");

  @override
  String get tapToStart => "Tap to start";

  @override
  RewindSetupLines setup(RewindSetup setup) => switch (setup) {
    RewindSetup.palette => (
      headlines: ["YOUR YEAR\nHAD A COLOR"],
      callout: "IT LOOKS GOOD\nON YOU!",
    ),
    RewindSetup.places => (
      headlines: ["YOU WENT\nPLACES."],
      callout: "THE CAMERA\nCAME TOO.",
    ),
    RewindSetup.people => (
      headlines: ["SOME FACES\nKEPT SHOWING\nUP."],
      callout: "LIKE, A LOT!",
    ),
    RewindSetup.busiestDay => (
      headlines: ["ONE DAY,\nYOU KEPT\nCLICKING."],
      callout: "AND CLICKING!",
    ),
    RewindSetup.newFaces => (
      headlines: ["THE CAST GOT\nBIGGER"],
      callout: "WELCOME TO THE FAM!",
    ),
    RewindSetup.favourites => (
      headlines: ["THE BEST\nOF THE BEST."],
      callout: "THEY DESERVE A STAR!",
    ),
    RewindSetup.ritual => (
      headlines: ["SOME THINGS\nYOU DID LIKE", "CLOCKWORK."],
      callout: "ALMOST TIME!",
    ),
    RewindSetup.ritualStreak => (
      headlines: ["YOU BUILT\nRITUALS."],
      callout: "ONE PHOTO A DAY.",
    ),
    RewindSetup.likes => (
      headlines: ["YOUR FEED\nWAS LIT!"],
      callout: "’SPECIALLY THIS ONE.",
    ),
    RewindSetup.mosaic => (
      headlines: ["IT ALL\nADDS UP."],
      callout: "PHOTO BY PHOTO.",
    ),
    RewindSetup.badge => (
      headlines: ["AFTER A YEAR\nLIKE THAT…"],
      callout: "YOU DESERVE A BADGE!",
    ),
  };

  @override
  String tunnelAgo(int days) =>
      days < 1 ? "EARLIER TODAY" : "${_counted(days, "DAY", "DAYS")} AGO";

  @override
  String get tunnelStartTitle => "IT STARTED HERE";

  @override
  RewindLines get tunnelStartBody =>
      (you: "Your first photo of the year.", me: "My first photo of the year.");

  @override
  String get tunnelGoOnHint => "TAP OR SWIPE UP TO GO ON";

  @override
  String get tunnelFlyBackHint => "SWIPE DOWN TO FLY BACK";

  @override
  String tunnelMomentEyebrow(DateTime day) =>
      "A ${_weekdays[day.weekday - 1].toUpperCase()} "
      "IN ${monthBanner(day.month)}";

  @override
  String get tunnelMomentTitle => "REMEMBER THIS?";

  @override
  RewindLines get tunnelMomentBody =>
      (you: "One moment from your year.", me: "One moment from my year.");

  @override
  String get tunnelLoading => "LOADING THE TAPE";

  @override
  String get tunnelFlyAgain => "FLY AGAIN";

  @override
  RewindLines get photosCountKicker => (
    you: "IN ${RewindEdition.year}, YOU CLICKED",
    me: "IN ${RewindEdition.year}, I CLICKED",
  );

  @override
  String memoriesUnit(int count) => count == 1 ? "memory" : "memories";

  @override
  RewindLines get topPercentKicker =>
      (you: "ACROSS ENTE, YOU’RE IN THE", me: "ACROSS ENTE, I’M IN THE");

  @override
  String topPercent(int percent) => "TOP $percent%";

  @override
  String memoriesSaved(int count) =>
      "${_counted(count, "memory", "memories")} saved, and counting!";

  @override
  String get placesQuestion => "WHERE DID YOU SHOOT MOST?";

  @override
  String get placesHint => "Tap a stamp to guess.";

  @override
  String placesPicked(String city) => "$city? Let’s check\nthe postmarks.";

  @override
  RewindLines placesHeading({required bool travelled}) => travelled
      ? (you: "YOUR PHOTOS TRAVELED", me: "MY PHOTOS TRAVELED")
      : (you: "YOUR TOP PLACE", me: "MY TOP PLACE");

  @override
  String distance(int km) => "${number(km)} KM";

  @override
  String placesWon(String city, int photos) =>
      "$city won with ${this.photos(photos)}.";

  @override
  String placesNext(List<String> cities) => switch (cities) {
    [final next] => "$next came next.",
    [final first, final second, ...] => "$first and $second came next.",
    _ => "",
  };

  @override
  String placesPlaced(String city, int place) =>
      "$city came ${place == 2 ? "2nd" : "3rd"}.";

  @override
  String placesHad(String city, int photos) => "$city had ${number(photos)}.";

  @override
  RewindLines get globeKicker =>
      (you: "YOUR PHOTOS FLEW", me: "MY PHOTOS FLEW");

  @override
  String globeLaps(double laps) =>
      "That’s ${laps.toStringAsFixed(1)} laps around the globe.";

  @override
  String globeLapShare(int percent) =>
      "That’s $percent% of a lap around the globe.";

  @override
  String get globeHint => "DRAG TO SPIN";

  @override
  String globeLabel(int km, String laps) =>
      "Your photos flew ${number(km)} kilometers. $laps";

  @override
  String globeTally(int cities, int countries) =>
      "${_counted(cities, "CITY", "CITIES")}"
      "  ·  "
      "${_counted(countries, "COUNTRY", "COUNTRIES")}";

  @override
  String get raceQuestion => "WHO SHOWED UP MOST?";

  @override
  String get raceHint => "Tap a face to guess.";

  @override
  String racePicked(String name) => "$name? bold choice";

  @override
  String raceOvertakes(String passer, String passed) =>
      "$passer OVERTAKES $passed!";

  @override
  String raceWinner(String name) => "$name SHOWED UP MOST!";

  @override
  RewindLines get raceCalledIt => (you: "YOU CALLED IT!", me: "I CALLED IT!");

  @override
  String get raceClose => "SO CLOSE!";

  @override
  String get raceMissed => "NOT THIS YEAR!";

  @override
  RewindLines get racePick => (you: "YOUR PICK", me: "MY PICK");

  @override
  RewindLines boothBilling(int place) => switch (place) {
    0 => (you: "YOUR NO. 1", me: "MY NO. 1"),
    1 => (you: "ALWAYS BY YOUR SIDE", me: "ALWAYS BY MY SIDE"),
    _ => (
      you: "${RewindEdition.year} WAS BETTER WITH",
      me: "${RewindEdition.year} WAS BETTER WITH",
    ),
  };

  @override
  String boothPhotos(int count) => "${photos(count)} this year!";

  @override
  RewindLines busiestDayKicker(int day, int month) {
    final onDay = "On ${_ordinal(day)} ${_months[month - 1]}";
    return (you: "$onDay, you took", me: "$onDay, I took");
  }

  @override
  String get busiestDayLine => "A memorable day indeed!";

  @override
  String newFacesTitle(int count) =>
      count == 1 ? "1 NEW FACE" : "${number(count)} NEW FACES";

  @override
  RewindLines newFacesLine(int count) => (
    you: "debuted in your gallery this year.",
    me: "debuted in my gallery this year.",
  );

  @override
  String colourName(rust.RewindColour colour) => switch (colour) {
    rust.RewindColour.cherryBomb => "CHERRY BOMB",
    rust.RewindColour.tangerinePop => "TANGERINE POP",
    rust.RewindColour.lemonDrop => "LEMON DROP",
    rust.RewindColour.pistachio => "PISTACHIO",
    rust.RewindColour.berryBlue => "BERRY BLUE",
    rust.RewindColour.lavenderFizz => "LAVENDER FIZZ",
    rust.RewindColour.bubblegum => "BUBBLEGUM",
    rust.RewindColour.hotCocoa => "HOT COCOA",
    rust.RewindColour.marshmallow => "MARSHMALLOW",
    rust.RewindColour.midnightCola => "MIDNIGHT COLA",
  };

  String _colourWord(rust.RewindColour colour) => switch (colour) {
    rust.RewindColour.cherryBomb => "red",
    rust.RewindColour.tangerinePop => "orange",
    rust.RewindColour.lemonDrop => "yellow",
    rust.RewindColour.pistachio => "green",
    rust.RewindColour.berryBlue => "blue",
    rust.RewindColour.lavenderFizz => "purple",
    rust.RewindColour.bubblegum => "pink",
    rust.RewindColour.hotCocoa => "brown",
    rust.RewindColour.marshmallow => "white",
    rust.RewindColour.midnightCola => "black",
  };

  @override
  RewindLines colourLine(int percent, rust.RewindColour colour) => (
    you: "$percent% of your photos were mostly ${_colourWord(colour)}.",
    me: "$percent% of my photos were mostly ${_colourWord(colour)}.",
  );

  @override
  String get favouritesTitle => "YOUR FAVORITES";

  @override
  String get myFavouritesTitle => "MY FAVORITES";

  @override
  String get myFavouriteTitle => "MY FAVORITE";

  @override
  String get favouritesLine => "Memories to cherish.";

  @override
  String get favouriteLine => "A memory to cherish.";

  @override
  String get favouritesLabel => "Your favorites. $favouritesLine";

  @override
  RewindLines get habitKicker =>
      (you: "YOUR WEEKLY RITUAL", me: "MY WEEKLY RITUAL");

  @override
  String clockHour(int hour) {
    final twelve = hour % 12 == 0 ? 12 : hour % 12;
    return "$twelve ${hour < 12 ? "AM" : "PM"}";
  }

  @override
  String habitTitle(int weekday, int hour) =>
      "${_weekdays[weekday - 1]}s, ${clockHour(hour)}";

  @override
  RewindLines habitLine(int percent, int weekday) => (
    you: "$percent% of your photos were taken on ${_weekdays[weekday - 1]}s.",
    me: "$percent% of my photos were taken on ${_weekdays[weekday - 1]}s.",
  );

  @override
  String habitLabel(String title, String line) =>
      "Your weekly ritual: $title. $line";

  @override
  String weekdayInitial(int weekday) => _weekdays[weekday - 1][0];

  @override
  String get crowdFavouriteTitle => "THE CROWD FAVORITE";

  @override
  RewindLines get crowdFavouriteLine =>
      (you: "Your most liked photo.", me: "My most liked photo.");

  @override
  String get crowdFavouriteLabel =>
      "The crowd favorite. ${crowdFavouriteLine.you}";

  @override
  RewindLines get streakKicker =>
      (you: "YOUR LONGEST STREAK", me: "MY LONGEST STREAK");

  @override
  String checkInsLabel(int count) =>
      count == 1 ? "Check-in\nthis year" : "Check-ins\nthis year";

  @override
  String ritualsContinuedLabel(int count) =>
      count == 1 ? "Ritual\ncontinued" : "Rituals\ncontinued";

  @override
  String get mostActiveMonthLabel => "Most active\nmonth";

  @override
  String streakLabel({
    required int streak,
    required int checkIns,
    required int month,
    required int continued,
  }) =>
      "Your longest ritual streak: ${number(streak)}. "
      "${_counted(checkIns, "check-in", "check-ins")} "
      "this year, most in ${monthName(month)}. "
      "${_counted(continued, "ritual", "rituals")} "
      "still going.";

  @override
  RewindLines get mosaicSelf => (you: "YOU", me: "ME");

  @override
  String get familiarFace => "A FAMILIAR FACE";

  @override
  String mosaicMoments(int count) =>
      "IN ${_counted(count, "MOMENT", "MOMENTS")}.";

  @override
  String get mosaicHint => "Tap or pinch to explore";

  @override
  RewindBadgeCopy badge(rust.RewindBadge badge) => switch (badge) {
    rust.RewindBadge.sunChaser => (
      title: "SUN CHASER",
      pronunciation: "/ˈsən ˌchā-sər/",
      definition:
          "Someone who regularly photographs sunrises, sunsets, and the golden-hour light.",
    ),
    rust.RewindBadge.consistencyChamp => (
      title: "CONSISTENCY\nCHAMP",
      pronunciation: "/kən-ˈsis-tən-sē champ/",
      definition:
          "Someone who showed up for their camera roll every single month. Come rain or shine.",
    ),
    rust.RewindBadge.unpaidPhotographer => (
      title: "UNPAID\nPHOTOGRAPHER",
      pronunciation: "/ən-ˈpād fə-ˈtä-grə-fər/",
      definition: "The reason the group chat has any photos at all.",
    ),
    rust.RewindBadge.mainCharacter => (
      title: "MAIN\nCHARACTER",
      pronunciation: "/ˈmān ˈker-ik-tər/",
      definition:
          "Someone who loves being photographed. Every scene was better with them in it.",
    ),
    rust.RewindBadge.earlyBird => (
      title: "EARLY BIRD",
      pronunciation: "/ˈər-lē ˈbərd/",
      definition:
          "Someone who’s up before the alarm and out before the crowds.",
    ),
    rust.RewindBadge.nightOwl => (
      title: "NIGHT OWL",
      pronunciation: "/ˈnīt ˌau̇l/",
      definition: "Someone whose camera has a thriving nightlife.",
    ),
    rust.RewindBadge.weekendStar => (
      title: "WEEKEND STAR",
      pronunciation: "/ˈwēk-end ˈstär/",
      definition: "Monday to Friday is rehearsal. The weekend is showtime.",
    ),
    rust.RewindBadge.pawparazzi => (
      title: "PAWPARAZZI",
      pronunciation: "/ˌpȯ-pə-ˈrät-sē/",
      definition:
          "Someone whose pet has had more photoshoots than most celebrities.",
    ),
    rust.RewindBadge.foodie => (
      title: "FOODIE",
      pronunciation: "/ˈfü-dē/",
      definition: "Someone whose phone always eats first.",
    ),
    rust.RewindBadge.plantParent => (
      title: "PLANT PARENT",
      pronunciation: "/ˈplant ˌper-ənt/",
      definition:
          "Someone who stops for every bloom and says hello to every leaf.",
    ),
    rust.RewindBadge.buildingBuff => (
      title: "BUILDING BUFF",
      pronunciation: "/ˈbil-diŋ ˈbəf/",
      definition: "Someone who sees art in arches, stairs and skylines.",
    ),
    rust.RewindBadge.screenshotCollector => (
      title: "SCREENSHOT\nCOLLECTOR",
      pronunciation: "/ˈskrēn-ˌshät kə-ˈlek-tər/",
      definition:
          "The keeper of receipts, recipes and every chat worth remembering.",
    ),
    rust.RewindBadge.hobbyHopper => (
      title: "HOBBY HOPPER",
      pronunciation: "/ˈhä-bē ˈhä-pər/",
      definition:
          "Jack of all trades, master of fun. A new passion every few months.",
    ),
    rust.RewindBadge.indoorKid => (
      title: "INDOOR KID",
      pronunciation: "/ˈin-dȯr ˈkid/",
      definition:
          "Someone who has mastered the art of cozy. The best moments happen at home, with the best people.",
    ),
    rust.RewindBadge.outOfOffice => (
      title: "OUT OF OFFICE",
      pronunciation: "/ˈau̇t əv ˈȯ-fəs/",
      definition: "Explorer whose suitcase barely got unpacked this year.",
    ),
    rust.RewindBadge.fullThrottle => (
      title: "FULL THROTTLE",
      pronunciation: "/ˈfu̇l ˈthrä-tᵊl/",
      definition:
          "Someone who doesn’t do “sit still”. If there’s a game, a trail or a finish line, they’re there.",
    ),
    rust.RewindBadge.eventHopper => (
      title: "EVENT HOPPER",
      pronunciation: "/i-ˈvent ˈhä-pər/",
      definition:
          "The friend with the best calendar. If it was happening, they were there.",
    ),
    rust.RewindBadge.alwaysRolling => (
      title: "ALWAYS\nROLLING",
      pronunciation: "/ˈȯl-wāz ˈrō-liŋ/",
      definition:
          "Someone who shoots more videos than photos. Every frame is priceless.",
    ),
    rust.RewindBadge.fitCheck => (
      title: "FIT CHECK",
      pronunciation: "/ˈfit ˌchek/",
      definition:
          "Someone who never wastes a good outfit. Every look gets documented.",
    ),
    rust.RewindBadge.artLover => (
      title: "ART LOVER",
      pronunciation: "/ˈärt ˈlə-vər/",
      definition:
          "Someone who finds art everywhere, from galleries to street corners.",
    ),
    rust.RewindBadge.limitedEdition => (
      title: "LIMITED\nEDITION",
      pronunciation: "/ˈli-mə-təd i-ˈdi-shən/",
      definition: "Someone who doesn’t snap everything, just the good stuff.",
    ),
    rust.RewindBadge.happySnapper => (
      title: "HAPPY SNAPPER",
      pronunciation: "/ˈha-pē ˈsna-pər/",
      definition:
          "Someone who photographs everything, because everything is worth it.",
    ),
    rust.RewindBadge.openingCredits => (
      title: "OPENING\nCREDITS",
      pronunciation: "/ˈō-pə-niŋ ˈkre-dits/",
      definition:
          "Someone whose story is just getting started. If this is the opening scene, the rest is going to be epic.",
    ),
    rust.RewindBadge.guestStar => (
      title: "GUEST STAR",
      pronunciation: "/ˈgest ˌstär/",
      definition:
          "Someone who saves their camera for the moments that matter, then goes all in.",
    ),
    rust.RewindBadge.mixedBag => (
      title: "MIXED BAG",
      pronunciation: "/ˈmikst ˈbag/",
      definition: "Impossible to label, and that’s the best part.",
    ),
  };

  @override
  String badgePronunciation(String pronunciation) => "$pronunciation · noun";

  @override
  String get badgeHeading => "WHAT MY PHOTOS\nSAY ABOUT ME";

  @override
  String get badgeHeadingLabel => "What my photos say about me";

  @override
  String badgeLabel(String title) => "$title badge";

  @override
  String get badgeHint => "Double tap to flip it again";

  @override
  String get scrapbookPhotos => "Photos clicked";

  @override
  String get scrapbookColour => "Color of the year";

  @override
  String get scrapbookPeople => "Top people";

  @override
  String get scrapbookPlaces => "Top places";

  @override
  String get scrapbookTop => "TOP";

  @override
  String get finaleTop => "WHAT A";

  @override
  String get finaleBottom => "YEAR!";

  @override
  String get finaleLabel => "What a year!";

  @override
  String get saveVideo => "Save video";

  @override
  String get savedVideo => "Saved";

  @override
  String get shareRewind => "Share your Rewind";

  @override
  String get endCardTagline => "Look back at\nyour year with";

  @override
  String get videoTitle => "MAKING YOUR VIDEO";

  @override
  List<String> get videoQuips => const [
    "Rewinding the tape",
    "Picking your best angles",
    "Teaching Ducky to edit",
    "Adding the soundtrack",
    "Polishing every frame",
    "Rolling the credits",
  ];

  @override
  String get videoPreparing => "Getting your photos ready";

  @override
  String get videoWrapped => "That’s a wrap!";

  @override
  String get videoDone => "All done";

  @override
  String get videoAlmostDone => "Almost there";

  @override
  String get videoKeepOpen => "Keep Ente open, this won’t take long";

  @override
  String get cancel => "Cancel";

  @override
  String get alreadySaved => "Already saved";

  @override
  String get backingUp => "Backing up to Ente";

  @override
  String get savedAndBackingUp => "Saved to your gallery, backing up to Ente";
}

import "package:intl/intl.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/copy/rewind_city_names.dart";
import "package:photos/ui/rewind/copy/rewind_copy.dart";
import "package:photos/ui/rewind/copy/rewind_copy_en.dart";

final _decimal = NumberFormat.decimalPattern("nl");

const _months = [
  "januari",
  "februari",
  "maart",
  "april",
  "mei",
  "juni",
  "juli",
  "augustus",
  "september",
  "oktober",
  "november",
  "december",
];

const _shortMonths = [
  "JAN",
  "FEB",
  "MRT",
  "APR",
  "MEI",
  "JUN",
  "JUL",
  "AUG",
  "SEP",
  "OKT",
  "NOV",
  "DEC",
];

const _weekdays = [
  "maandag",
  "dinsdag",
  "woensdag",
  "donderdag",
  "vrijdag",
  "zaterdag",
  "zondag",
];

String _capitalised(String word) =>
    "${word[0].toUpperCase()}${word.substring(1)}";

class DutchRewindCopy extends RewindCopy {
  const DutchRewindCopy();

  String _counted(int value, String one, String many) =>
      "${number(value)} ${value == 1 ? one : many}";

  @override
  String number(int value) => _decimal.format(value);

  @override
  String photoTally(String number, int count) => "$number ${photoUnit(count)}";

  @override
  String photoUnit(int count) => count == 1 ? "foto" : "foto’s";

  @override
  Map<String, String> get cityNames => dutchCityNames;

  @override
  String shortDate(int day, int month, int year) =>
      "$day ${_shortMonths[month - 1]} $year";

  @override
  String monthBanner(int month) => _months[month - 1].toUpperCase();

  @override
  String monthName(int month) => _capitalised(_months[month - 1]);

  @override
  String get close => "Sluiten";

  @override
  String get playMusic => "Muziek afspelen";

  @override
  String get muteMusic => "Muziek dempen";

  @override
  String get share => "Delen";

  @override
  String get shareVideo => "Video delen";

  @override
  String get nextCard => "Volgende kaart";

  @override
  String pageOf(int page, int count) => "Pagina $page van $count";

  @override
  String get dismiss => "Verbergen";

  @override
  String get watch => "Bekijken";

  @override
  String get watchAgain => "Opnieuw bekijken";

  @override
  String get resume => "Verder kijken";

  @override
  String get newStatus => "Nieuw";

  @override
  String get newSticker => "NIEUW";

  @override
  String progress(int page, int count) => "$page van $count";

  @override
  String get readyTitle => "Je Rewind ${RewindEdition.year} staat klaar";

  @override
  String get readyBody => "Je jaar in foto’s. Klaar wanneer jij het bent.";

  @override
  String get newCardsTitle =>
      "Je Rewind ${RewindEdition.year} heeft nieuwe kaarten";

  @override
  String get newCardsBody => "Open hem opnieuw om te zien wat er nieuw is.";

  @override
  RewindLines get coverTagline =>
      (you: "JOUW JAAR IN FOTO’S", me: "MIJN JAAR IN FOTO’S");

  @override
  String get tapToStart => "Tik om te starten";

  @override
  RewindSetupLines setup(RewindSetup setup) => switch (setup) {
    RewindSetup.palette => (
      headlines: ["JOUW JAAR\nHAD EEN KLEUR"],
      callout: "HET STAAT\nJE GOED!",
    ),
    RewindSetup.places => (
      headlines: ["JE TROK\nEROPUIT."],
      callout: "DE CAMERA\nGING MEE.",
    ),
    RewindSetup.people => (
      headlines: ["SOMMIGE\nGEZICHTEN BLEVEN\nOPDUIKEN."],
      callout: "ECHT HEEL VAAK!",
    ),
    RewindSetup.busiestDay => (
      headlines: ["OP EEN DAG\nBLEEF JE MAAR\nKLIKKEN."],
      callout: "EN KLIKKEN!",
    ),
    RewindSetup.newFaces => (
      headlines: ["DE CAST WERD\nGROTER"],
      callout: "WELKOM IN DE FAMILIE!",
    ),
    RewindSetup.favourites => (
      headlines: ["HET BESTE\nVAN HET BESTE."],
      callout: "DIE VERDIENEN EEN STER!",
    ),
    RewindSetup.ritual => (
      headlines: ["SOMMIGE DINGEN\nLIEPEN ALS EEN", "KLOKJE."],
      callout: "BIJNA TIJD!",
    ),
    RewindSetup.ritualStreak => (
      headlines: ["JE BOUWDE\nRITUELEN OP."],
      callout: "ÉÉN FOTO PER DAG.",
    ),
    RewindSetup.likes => (
      headlines: ["JOUW FEED\nGING LOS!"],
      callout: "VOORAL DEZE!",
    ),
    RewindSetup.mosaic => (
      headlines: ["HET TELT\nALLEMAAL OP."],
      callout: "FOTO VOOR FOTO.",
    ),
    RewindSetup.badge => (
      headlines: ["NA EEN JAAR\nALS DIT…"],
      callout: "VERDIEN JE EEN BADGE!",
    ),
  };

  @override
  String tunnelAgo(int days) =>
      days < 1 ? "EERDER VANDAAG" : "${_counted(days, "DAG", "DAGEN")} GELEDEN";

  @override
  String get tunnelStartTitle => "HIER BEGON HET";

  @override
  RewindLines get tunnelStartBody => (
    you: "Je eerste foto van het jaar.",
    me: "Mijn eerste foto van het jaar.",
  );

  @override
  String get tunnelGoOnHint => "TIK OF VEEG OMHOOG OM VERDER TE GAAN";

  @override
  String get tunnelFlyBackHint => "VEEG OMLAAG OM TERUG TE VLIEGEN";

  @override
  String tunnelMomentEyebrow(DateTime day) =>
      "EEN ${_weekdays[day.weekday - 1].toUpperCase()} "
      "IN ${monthBanner(day.month)}";

  @override
  String get tunnelMomentTitle => "WEET JE NOG?";

  @override
  RewindLines get tunnelMomentBody =>
      (you: "Eén moment uit jouw jaar.", me: "Eén moment uit mijn jaar.");

  @override
  String get tunnelLoading => "BANDJE WORDT GELADEN";

  @override
  String get tunnelFlyAgain => "NOG EEN KEER";

  @override
  RewindLines get photosCountKicker => (
    you: "IN ${RewindEdition.year} MAAKTE JE",
    me: "IN ${RewindEdition.year} MAAKTE IK",
  );

  @override
  String memoriesUnit(int count) =>
      count == 1 ? "herinnering" : "herinneringen";

  @override
  RewindLines get topPercentKicker =>
      (you: "OP ENTE HOOR JE BIJ DE", me: "OP ENTE HOOR IK BIJ DE");

  @override
  String topPercent(int percent) => "TOP $percent%";

  @override
  String memoriesSaved(int count) =>
      "${_counted(count, "herinnering", "herinneringen")} bewaard, "
      "en de teller loopt nog!";

  @override
  String get placesQuestion => "WAAR FOTOGRAFEERDE JE HET MEEST?";

  @override
  String get placesHint => "Tik op een postzegel om te raden.";

  @override
  String placesPicked(String city) =>
      "$city? Eens kijken wat\nde poststempels zeggen.";

  @override
  RewindLines placesHeading({required bool travelled}) => travelled
      ? (you: "JE FOTO’S REISDEN", me: "MIJN FOTO’S REISDEN")
      : (you: "JOUW TOPPLEK", me: "MIJN TOPPLEK");

  @override
  String distance(int km) => "${number(km)} KM";

  @override
  String placesWon(String city, int photos) =>
      "$city won met ${this.photos(photos)}.";

  @override
  String placesNext(List<String> cities) => switch (cities) {
    [final next] => "Daarna kwam $next.",
    [final first, final second, ...] => "Daarna kwamen $first en $second.",
    _ => "",
  };

  @override
  String placesPlaced(String city, int place) =>
      "$city werd ${place == 2 ? "tweede" : "derde"}.";

  @override
  String placesHad(String city, int photos) =>
      "$city had er ${number(photos)}.";

  @override
  RewindLines get globeKicker =>
      (you: "JE FOTO’S VLOGEN", me: "MIJN FOTO’S VLOGEN");

  @override
  String globeLaps(double laps) =>
      "Dat is ${laps.toStringAsFixed(1).replaceFirst(".", ",")} keer "
      "de wereld rond.";

  @override
  String globeLapShare(int percent) =>
      "Dat is $percent% van een rondje om de wereld.";

  @override
  String get globeHint => "SLEEP OM TE DRAAIEN";

  @override
  String globeLabel(int km, String laps) =>
      "Je foto’s vlogen ${number(km)} kilometer. $laps";

  @override
  String globeTally(int cities, int countries) =>
      "${_counted(cities, "STAD", "STEDEN")}"
      "  ·  "
      "${_counted(countries, "LAND", "LANDEN")}";

  @override
  String get raceQuestion => "WIE STOND HET VAAKST OP DE FOTO?";

  @override
  String get raceHint => "Tik op een gezicht om te raden.";

  @override
  String racePicked(String name) => "$name? gedurfde keuze";

  @override
  String raceOvertakes(String passer, String passed) =>
      "$passer HAALT $passed IN!";

  @override
  String raceWinner(String name) => "$name STOND ER HET VAAKST OP!";

  @override
  RewindLines get raceCalledIt =>
      (you: "GOED GERADEN!", me: "IK HAD HET GOED!");

  @override
  String get raceClose => "NET NIET!";

  @override
  String get raceMissed => "DIT JAAR NIET!";

  @override
  RewindLines get racePick => (you: "JOUW GOK", me: "MIJN GOK");

  @override
  RewindLines boothBilling(int place) => switch (place) {
    0 => (you: "JOUW NR. 1", me: "MIJN NR. 1"),
    1 => (you: "ALTIJD AAN JOUW ZIJ", me: "ALTIJD AAN MIJN ZIJ"),
    _ => (
      you: "${RewindEdition.year} WAS BETER MET",
      me: "${RewindEdition.year} WAS BETER MET",
    ),
  };

  @override
  String boothPhotos(int count) => "${photos(count)} dit jaar!";

  @override
  RewindLines busiestDayKicker(int day, int month) {
    final onDay = "Op $day ${_months[month - 1]}";
    return (you: "$onDay maakte je", me: "$onDay maakte ik");
  }

  @override
  String get busiestDayLine => "Een dag om nooit te vergeten!";

  @override
  String newFacesTitle(int count) =>
      count == 1 ? "1 NIEUW GEZICHT" : "${number(count)} NIEUWE GEZICHTEN";

  @override
  RewindLines newFacesLine(int count) {
    final debuted = count == 1 ? "debuteerde" : "debuteerden";
    return (
      you: "$debuted dit jaar in je galerij.",
      me: "$debuted dit jaar in mijn galerij.",
    );
  }

  @override
  String colourName(rust.RewindColour colour) => switch (colour) {
    rust.RewindColour.cherryBomb => "KERSENBOM",
    rust.RewindColour.tangerinePop => "MANDARIJNTJE",
    rust.RewindColour.lemonDrop => "CITROENZUURTJE",
    rust.RewindColour.pistachio => "PISTACHE",
    rust.RewindColour.berryBlue => "BESSENBLAUW",
    rust.RewindColour.lavenderFizz => "LAVENDELBRUIS",
    rust.RewindColour.bubblegum => "KAUWGOM",
    rust.RewindColour.hotCocoa => "CHOCOLADEMELK",
    rust.RewindColour.marshmallow => "SPEKJE",
    rust.RewindColour.midnightCola => "MIDDERNACHTCOLA",
  };

  String _colourWord(rust.RewindColour colour) => switch (colour) {
    rust.RewindColour.cherryBomb => "rood",
    rust.RewindColour.tangerinePop => "oranje",
    rust.RewindColour.lemonDrop => "geel",
    rust.RewindColour.pistachio => "groen",
    rust.RewindColour.berryBlue => "blauw",
    rust.RewindColour.lavenderFizz => "paars",
    rust.RewindColour.bubblegum => "roze",
    rust.RewindColour.hotCocoa => "bruin",
    rust.RewindColour.marshmallow => "wit",
    rust.RewindColour.midnightCola => "zwart",
  };

  @override
  RewindLines colourLine(int percent, rust.RewindColour colour) => (
    you: "$percent% van je foto’s waren vooral ${_colourWord(colour)}.",
    me: "$percent% van mijn foto’s waren vooral ${_colourWord(colour)}.",
  );

  @override
  String get favouritesTitle => "JOUW FAVORIETEN";

  @override
  String get myFavouritesTitle => "MIJN FAVORIETEN";

  @override
  String get myFavouriteTitle => "MIJN FAVORIET";

  @override
  String get favouritesLine => "Herinneringen om te koesteren.";

  @override
  String get favouriteLine => "Een herinnering om te koesteren.";

  @override
  String get favouritesLabel => "Jouw favorieten. $favouritesLine";

  @override
  RewindLines get habitKicker =>
      (you: "JOUW WEKELIJKSE RITUEEL", me: "MIJN WEKELIJKSE RITUEEL");

  @override
  String clockHour(int hour) => "${hour.toString().padLeft(2, "0")}:00";

  @override
  String habitTitle(int weekday, int hour) =>
      "${_capitalised(_weekdays[weekday - 1])}s, "
      "${hour == 0 ? "middernacht" : "$hour uur"}";

  @override
  RewindLines habitLine(int percent, int weekday) => (
    you: "Je maakte $percent% van je foto’s op ${_weekdays[weekday - 1]}.",
    me: "Ik maakte $percent% van mijn foto’s op ${_weekdays[weekday - 1]}.",
  );

  @override
  String habitLabel(String title, String line) =>
      "Jouw wekelijkse ritueel: $title. $line";

  @override
  String weekdayInitial(int weekday) => _weekdays[weekday - 1][0].toUpperCase();

  @override
  String get crowdFavouriteTitle => "DE PUBLIEKSFAVORIET";

  @override
  RewindLines get crowdFavouriteLine => (
    you: "Je foto met de meeste likes.",
    me: "Mijn foto met de meeste likes.",
  );

  @override
  String get crowdFavouriteLabel =>
      "De publieksfavoriet. ${crowdFavouriteLine.you}";

  @override
  RewindLines get streakKicker =>
      (you: "JOUW LANGSTE REEKS", me: "MIJN LANGSTE REEKS");

  @override
  String checkInsLabel(int count) =>
      count == 1 ? "Check-in\ndit jaar" : "Check-ins\ndit jaar";

  @override
  String ritualsContinuedLabel(int count) =>
      count == 1 ? "Ritueel\nloopt nog" : "Rituelen\nlopen nog";

  @override
  String get mostActiveMonthLabel => "Actiefste\nmaand";

  @override
  String streakLabel({
    required int streak,
    required int checkIns,
    required int month,
    required int continued,
  }) =>
      "Je langste ritueelreeks: ${number(streak)}. "
      "${_counted(checkIns, "check-in", "check-ins")} "
      "dit jaar, de meeste in ${_months[month - 1]}. "
      "${_counted(continued, "ritueel loopt", "rituelen lopen")} nog.";

  @override
  RewindLines get mosaicSelf => (you: "JIJ", me: "IK");

  @override
  String get familiarFace => "EEN BEKEND GEZICHT";

  @override
  String mosaicMoments(int count) =>
      "IN ${_counted(count, "MOMENT", "MOMENTEN")}.";

  @override
  String get mosaicHint => "Tik of zoom om te ontdekken";

  @override
  RewindBadgeCopy badge(rust.RewindBadge badge) {
    final english = const EnglishRewindCopy().badge(badge);
    return (
      title: english.title,
      pronunciation: english.pronunciation,
      definition: switch (badge) {
        rust.RewindBadge.sunChaser =>
          "Iemand die steeds weer zonsopkomsten, zonsondergangen en het gouden uur vastlegt.",
        rust.RewindBadge.consistencyChamp =>
          "Iemand die er elke maand weer stond voor de filmrol. Weer of geen weer.",
        rust.RewindBadge.unpaidPhotographer =>
          "De reden dat de groepsapp überhaupt foto’s heeft.",
        rust.RewindBadge.mainCharacter =>
          "Iemand die graag op de foto gaat. Elke scène werd er beter van.",
        rust.RewindBadge.earlyBird =>
          "Iemand die al op is voordat de wekker gaat, en de deur uit voordat het druk wordt.",
        rust.RewindBadge.nightOwl =>
          "Iemand van wie de camera een bruisend nachtleven heeft.",
        rust.RewindBadge.weekendStar =>
          "Maandag tot vrijdag zijn de repetities. In het weekend gaat het doek op.",
        rust.RewindBadge.pawparazzi =>
          "Iemand van wie het huisdier meer fotoshoots heeft gehad dan de meeste beroemdheden.",
        rust.RewindBadge.foodie =>
          "Iemand bij wie de telefoon altijd als eerste eet.",
        rust.RewindBadge.plantParent =>
          "Iemand die stopt voor elke bloem en elk blaadje gedag zegt.",
        rust.RewindBadge.buildingBuff =>
          "Iemand die kunst ziet in bogen, trappen en skylines.",
        rust.RewindBadge.screenshotCollector =>
          "Hoeder van bonnetjes, recepten en elke chat die het bewaren waard is.",
        rust.RewindBadge.hobbyHopper =>
          "Van alle markten thuis, meester in plezier. Om de paar maanden een nieuwe passie.",
        rust.RewindBadge.indoorKid =>
          "Iemand die gezelligheid tot kunst heeft verheven. De mooiste momenten beleef je thuis, met de leukste mensen.",
        rust.RewindBadge.outOfOffice =>
          "Ontdekkingsreiziger van wie de koffer dit jaar amper werd uitgepakt.",
        rust.RewindBadge.fullThrottle =>
          "Iemand voor wie “stilzitten” niet bestaat. Een wedstrijd, een parcours of een finishlijn? Altijd van de partij.",
        rust.RewindBadge.eventHopper =>
          "Degene met de volste agenda. Was er iets te doen, dan was die erbij.",
        rust.RewindBadge.alwaysRolling =>
          "Iemand die meer video’s dan foto’s maakt. Elk frame is goud waard.",
        rust.RewindBadge.fitCheck =>
          "Iemand die geen goede outfit laat verloren gaan. Elke look wordt vastgelegd.",
        rust.RewindBadge.artLover =>
          "Iemand die overal kunst vindt, van galerieën tot straathoeken.",
        rust.RewindBadge.limitedEdition =>
          "Iemand die niet alles vastlegt, alleen de krenten uit de pap.",
        rust.RewindBadge.happySnapper =>
          "Iemand die alles fotografeert, want alles is het waard.",
        rust.RewindBadge.openingCredits =>
          "Iemand van wie het verhaal net begint. Als dit de openingsscène is, wordt de rest episch.",
        rust.RewindBadge.guestStar =>
          "Iemand die de camera bewaart voor de momenten die ertoe doen, en dan alles geeft.",
        rust.RewindBadge.mixedBag =>
          "Niet in een hokje te stoppen, en dat is juist het mooie.",
      },
    );
  }

  @override
  String badgePronunciation(String pronunciation) => "$pronunciation · znw.";

  @override
  String get badgeHeading => "WAT MIJN FOTO’S\nOVER MIJ ZEGGEN";

  @override
  String get badgeHeadingLabel => "Wat mijn foto’s over mij zeggen";

  @override
  String badgeLabel(String title) => "Badge $title";

  @override
  String get badgeHint => "Tik twee keer om hem nog eens om te draaien";

  @override
  String get scrapbookPhotos => "Foto’s gemaakt";

  @override
  String get scrapbookColour => "Kleur van het jaar";

  @override
  String get scrapbookPeople => "Topmensen";

  @override
  String get scrapbookPlaces => "Topplekken";

  @override
  String get scrapbookTop => "TOP";

  @override
  String get finaleTop => "WAT EEN";

  @override
  String get finaleBottom => "JAAR!";

  @override
  String get finaleLabel => "Wat een jaar!";

  @override
  String get saveVideo => "Video opslaan";

  @override
  String get savedVideo => "Opgeslagen";

  @override
  String get shareRewind => "Deel je Rewind";

  @override
  String get endCardTagline => "Blik terug op\nje jaar met";

  @override
  String get videoTitle => "JE VIDEO IN DE MAAK";

  @override
  List<String> get videoQuips => const [
    "Het bandje terugspoelen",
    "Je beste kanten uitzoeken",
    "Ducky leren monteren",
    "De soundtrack toevoegen",
    "Elk frame oppoetsen",
    "De aftiteling laten rollen",
  ];

  @override
  String get videoPreparing => "Je foto’s klaarzetten";

  @override
  String get videoWrapped => "Klaar is Kees!";

  @override
  String get videoDone => "Helemaal klaar";

  @override
  String get videoAlmostDone => "Nog heel even";

  @override
  String get videoKeepOpen => "Houd Ente open, het duurt niet lang";

  @override
  String get cancel => "Annuleren";

  @override
  String get alreadySaved => "Al opgeslagen";

  @override
  String get backingUp => "Back-up naar Ente wordt gemaakt";

  @override
  String get savedAndBackingUp =>
      "Opgeslagen in je galerij, back-up naar Ente wordt gemaakt";
}

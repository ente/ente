import "package:intl/intl.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/copy/rewind_city_names.dart";
import "package:photos/ui/rewind/copy/rewind_copy.dart";
import "package:photos/ui/rewind/copy/rewind_copy_en.dart";

final _decimal = NumberFormat.decimalPattern("de");

const _months = [
  "Januar",
  "Februar",
  "März",
  "April",
  "Mai",
  "Juni",
  "Juli",
  "August",
  "September",
  "Oktober",
  "November",
  "Dezember",
];

const _shortMonths = [
  "JAN",
  "FEB",
  "MÄR",
  "APR",
  "MAI",
  "JUN",
  "JUL",
  "AUG",
  "SEP",
  "OKT",
  "NOV",
  "DEZ",
];

const _weekdays = [
  "Montag",
  "Dienstag",
  "Mittwoch",
  "Donnerstag",
  "Freitag",
  "Samstag",
  "Sonntag",
];

String _weekly(int weekday) => "${_weekdays[weekday - 1]}s";

class GermanRewindCopy extends RewindCopy {
  const GermanRewindCopy();

  String _counted(int value, String one, String many) =>
      "${number(value)} ${value == 1 ? one : many}";

  @override
  String number(int value) =>
      _decimal.format(value).replaceAll(RegExp("[\u00a0\u202f]"), " ");

  @override
  String photoTally(String number, int count) => "$number ${photoUnit(count)}";

  @override
  String photoUnit(int count) => count == 1 ? "Foto" : "Fotos";

  @override
  Map<String, String> get cityNames => germanCityNames;

  @override
  String shortDate(int day, int month, int year) =>
      "$day. ${_shortMonths[month - 1]} $year";

  @override
  String monthBanner(int month) => _months[month - 1].toUpperCase();

  @override
  String monthName(int month) => _months[month - 1];

  @override
  String get close => "Schließen";

  @override
  String get playMusic => "Musik abspielen";

  @override
  String get muteMusic => "Musik stummschalten";

  @override
  String get share => "Teilen";

  @override
  String get shareVideo => "Video teilen";

  @override
  String get nextCard => "Nächste Karte";

  @override
  String pageOf(int page, int count) => "Seite $page von $count";

  @override
  String get dismiss => "Ausblenden";

  @override
  String get watch => "Ansehen";

  @override
  String get watchAgain => "Nochmal ansehen";

  @override
  String get resume => "Weiterschauen";

  @override
  String get newStatus => "Neu";

  @override
  String get newSticker => "NEU";

  @override
  String progress(int page, int count) => "$page von $count";

  @override
  String get readyTitle => "Dein Rewind ${RewindEdition.year} ist da";

  @override
  String get readyBody =>
      "Dein Jahr in Fotos. Schau rein, wann immer du magst.";

  @override
  String get newCardsTitle =>
      "Dein Rewind ${RewindEdition.year} hat neue Karten";

  @override
  String get newCardsBody => "Schau nochmal rein und entdecke, was neu ist.";

  @override
  RewindLines get coverTagline =>
      (you: "DEIN JAHR IN FOTOS", me: "MEIN JAHR IN FOTOS");

  @override
  String get tapToStart => "Zum Starten tippen";

  @override
  RewindSetupLines setup(RewindSetup setup) => switch (setup) {
    RewindSetup.palette => (
      headlines: ["DEIN JAHR IN\nEINER FARBE"],
      callout: "STEHT DIR\nRICHTIG GUT!",
    ),
    RewindSetup.places => (
      headlines: ["DU WARST\nUNTERWEGS."],
      callout: "DIE KAMERA\nWAR DABEI.",
    ),
    RewindSetup.people => (
      headlines: ["MANCHE GESICHTER\nTAUCHTEN IMMER\nWIEDER AUF."],
      callout: "ABER SOWAS VON!",
    ),
    RewindSetup.busiestDay => (
      headlines: ["AN EINEM TAG\nHAST DU NUR\nGEKLICKT."],
      callout: "UND GEKLICKT!",
    ),
    RewindSetup.newFaces => (
      headlines: ["DIE BESETZUNG\nWURDE GRÖSSER"],
      callout: "WILLKOMMEN IN DER FAM!",
    ),
    RewindSetup.favourites => (
      headlines: ["DAS BESTE\nVOM BESTEN."],
      callout: "DIE VERDIENEN EINEN STERN!",
    ),
    RewindSetup.ritual => (
      headlines: ["MANCHE DINGE\nLIEFEN WIE EIN", "UHRWERK."],
      callout: "GLEICH SO WEIT!",
    ),
    RewindSetup.ritualStreak => (
      headlines: ["DU BAUTEST\nRITUALE AUF."],
      callout: "EIN FOTO AM TAG.",
    ),
    RewindSetup.likes => (
      headlines: ["DEIN FEED GING\nRICHTIG AB!"],
      callout: "VOR ALLEM DAS HIER!",
    ),
    RewindSetup.mosaic => (
      headlines: ["ALLES FÜGT\nSICH."],
      callout: "FOTO FÜR FOTO.",
    ),
    RewindSetup.badge => (
      headlines: ["NACH SO EINEM\nJAHR …"],
      callout: "VERDIENST DU EIN ABZEICHEN!",
    ),
  };

  @override
  String tunnelAgo(int days) =>
      days < 1 ? "HEUTE" : "VOR ${_counted(days, "TAG", "TAGEN")}";

  @override
  String get tunnelStartTitle => "HIER GING’S LOS";

  @override
  RewindLines get tunnelStartBody =>
      (you: "Dein erstes Foto des Jahres.", me: "Mein erstes Foto des Jahres.");

  @override
  String get tunnelGoOnHint => "TIPPEN ODER NACH OBEN WISCHEN";

  @override
  String get tunnelFlyBackHint => "ZUM ZURÜCKFLIEGEN NACH UNTEN WISCHEN";

  @override
  String tunnelMomentEyebrow(DateTime day) =>
      "EIN ${_weekdays[day.weekday - 1].toUpperCase()} "
      "IM ${monthBanner(day.month)}";

  @override
  String get tunnelMomentTitle => "WEISST DU NOCH?";

  @override
  RewindLines get tunnelMomentBody =>
      (you: "Ein Moment aus deinem Jahr.", me: "Ein Moment aus meinem Jahr.");

  @override
  String get tunnelLoading => "KASSETTE WIRD EINGELEGT";

  @override
  String get tunnelFlyAgain => "NOCHMAL FLIEGEN";

  @override
  RewindLines get photosCountKicker => (
    you: "${RewindEdition.year} SAMMELTEST DU",
    me: "${RewindEdition.year} SAMMELTE ICH",
  );

  @override
  String memoriesUnit(int count) => count == 1 ? "Erinnerung" : "Erinnerungen";

  @override
  RewindLines get topPercentKicker =>
      (you: "BEI ENTE GEHÖRST DU ZU DEN", me: "BEI ENTE GEHÖRE ICH ZU DEN");

  @override
  String topPercent(int percent) => "TOP $percent%";

  @override
  String memoriesSaved(int count) =>
      "${_counted(count, "Erinnerung", "Erinnerungen")} gesichert, "
      "Tendenz steigend!";

  @override
  String get placesQuestion => "WO HAST DU AM MEISTEN GEKNIPST?";

  @override
  String get placesHint => "Tippe auf eine Briefmarke und rate.";

  @override
  String placesPicked(String city) =>
      "$city? Mal sehen, was\ndie Poststempel sagen.";

  @override
  RewindLines placesHeading({required bool travelled}) => travelled
      ? (you: "DEINE FOTOS REISTEN", me: "MEINE FOTOS REISTEN")
      : (you: "DEIN TOP-ORT", me: "MEIN TOP-ORT");

  @override
  String distance(int km) => "${number(km)} KM";

  @override
  String placesWon(String city, int photos) =>
      "$city gewann mit ${this.photos(photos)}.";

  @override
  String placesNext(List<String> cities) => switch (cities) {
    [final next] => "Dahinter landete $next.",
    [final first, final second, ...] => "Dahinter landeten $first und $second.",
    _ => "",
  };

  @override
  String placesPlaced(String city, int place) =>
      "$city landete auf Platz ${place == 2 ? "zwei" : "drei"}.";

  @override
  String placesHad(String city, int photos) =>
      "$city kam auf ${number(photos)}.";

  @override
  RewindLines get globeKicker =>
      (you: "DEINE FOTOS FLOGEN", me: "MEINE FOTOS FLOGEN");

  @override
  String globeLaps(double laps) =>
      "Das sind ${laps.toStringAsFixed(1).replaceFirst(".", ",")} Runden "
      "um die Erde.";

  @override
  String globeLapShare(int percent) =>
      "Das sind $percent% einer Runde um die Erde.";

  @override
  String get globeHint => "ZUM DREHEN ZIEHEN";

  @override
  String globeLabel(int km, String laps) =>
      "Deine Fotos flogen ${number(km)} Kilometer. $laps";

  @override
  String globeTally(int cities, int countries) =>
      "${_counted(cities, "STADT", "STÄDTE")}"
      "  ·  "
      "${_counted(countries, "LAND", "LÄNDER")}";

  @override
  String get raceQuestion => "WER TAUCHTE AM HÄUFIGSTEN AUF?";

  @override
  String get raceHint => "Tippe auf ein Gesicht und rate.";

  @override
  String racePicked(String name) => "$name? mutige Wahl";

  @override
  String raceOvertakes(String passer, String passed) =>
      "$passer ÜBERHOLT $passed!";

  @override
  String raceWinner(String name) => "$name TAUCHTE AM HÄUFIGSTEN AUF!";

  @override
  RewindLines get raceCalledIt =>
      (you: "DU HAST’S GEWUSST!", me: "ICH HAB’S GEWUSST!");

  @override
  String get raceClose => "KNAPP DANEBEN!";

  @override
  String get raceMissed => "DIESES JAHR NICHT!";

  @override
  RewindLines get racePick => (you: "DEIN TIPP", me: "MEIN TIPP");

  @override
  RewindLines boothBilling(int place) => switch (place) {
    0 => (you: "DEINE NR. 1", me: "MEINE NR. 1"),
    1 => (you: "IMMER AN DEINER SEITE", me: "IMMER AN MEINER SEITE"),
    _ => (
      you: "${RewindEdition.year} WAR SCHÖNER MIT",
      me: "${RewindEdition.year} WAR SCHÖNER MIT",
    ),
  };

  @override
  String boothPhotos(int count) => "${photos(count)} dieses Jahr!";

  @override
  RewindLines busiestDayKicker(int day, int month) {
    final onDay = "Am $day. ${_months[month - 1]}";
    return (you: "$onDay machtest du", me: "$onDay machte ich");
  }

  @override
  String get busiestDayLine => "Ein Tag, den man nicht vergisst!";

  @override
  String newFacesTitle(int count) =>
      count == 1 ? "1 NEUES GESICHT" : "${number(count)} NEUE GESICHTER";

  @override
  RewindLines newFacesLine(int count) {
    final premiered = count == 1 ? "feierte" : "feierten";
    return (
      you: "$premiered dieses Jahr in deiner Galerie Premiere.",
      me: "$premiered dieses Jahr in meiner Galerie Premiere.",
    );
  }

  @override
  String colourName(rust.RewindColour colour) => switch (colour) {
    rust.RewindColour.cherryBomb => "KIRSCHBOMBE",
    rust.RewindColour.tangerinePop => "ORANGENLIMO",
    rust.RewindColour.lemonDrop => "ZITRONENBONBON",
    rust.RewindColour.pistachio => "PISTAZIENEIS",
    rust.RewindColour.berryBlue => "BLAUBEERE",
    rust.RewindColour.lavenderFizz => "LAVENDELBRAUSE",
    rust.RewindColour.bubblegum => "ZUCKERWATTE",
    rust.RewindColour.hotCocoa => "HEISSE SCHOKI",
    rust.RewindColour.marshmallow => "MÄUSESPECK",
    rust.RewindColour.midnightCola => "LAKRITZ",
  };

  String _colourWord(rust.RewindColour colour) => switch (colour) {
    rust.RewindColour.cherryBomb => "rot",
    rust.RewindColour.tangerinePop => "orange",
    rust.RewindColour.lemonDrop => "gelb",
    rust.RewindColour.pistachio => "grün",
    rust.RewindColour.berryBlue => "blau",
    rust.RewindColour.lavenderFizz => "lila",
    rust.RewindColour.bubblegum => "rosa",
    rust.RewindColour.hotCocoa => "braun",
    rust.RewindColour.marshmallow => "weiß",
    rust.RewindColour.midnightCola => "schwarz",
  };

  @override
  RewindLines colourLine(int percent, rust.RewindColour colour) => (
    you: "$percent% deiner Fotos waren überwiegend ${_colourWord(colour)}.",
    me: "$percent% meiner Fotos waren überwiegend ${_colourWord(colour)}.",
  );

  @override
  String get favouritesTitle => "DEINE FAVORITEN";

  @override
  String get myFavouritesTitle => "MEINE FAVORITEN";

  @override
  String get myFavouriteTitle => "MEIN FAVORIT";

  @override
  String get favouritesLine => "Erinnerungen fürs Herz.";

  @override
  String get favouriteLine => "Eine Erinnerung fürs Herz.";

  @override
  String get favouritesLabel => "Deine Favoriten. $favouritesLine";

  @override
  RewindLines get habitKicker =>
      (you: "DEIN WÖCHENTLICHES RITUAL", me: "MEIN WÖCHENTLICHES RITUAL");

  @override
  String clockHour(int hour) => "${hour.toString().padLeft(2, "0")}:00";

  @override
  String habitTitle(int weekday, int hour) => "${_weekly(weekday)}, $hour Uhr";

  @override
  RewindLines habitLine(int percent, int weekday) {
    final weekly = _weekly(weekday).toLowerCase();
    return (
      you: "$percent% deiner Fotos entstanden $weekly.",
      me: "$percent% meiner Fotos entstanden $weekly.",
    );
  }

  @override
  String habitLabel(String title, String line) =>
      "Dein wöchentliches Ritual: $title. $line";

  @override
  String weekdayInitial(int weekday) => _weekdays[weekday - 1][0];

  @override
  String get crowdFavouriteTitle => "DER PUBLIKUMSLIEBLING";

  @override
  RewindLines get crowdFavouriteLine => (
    you: "Dein Foto mit den meisten Likes.",
    me: "Mein Foto mit den meisten Likes.",
  );

  @override
  String get crowdFavouriteLabel =>
      "Der Publikumsliebling. ${crowdFavouriteLine.you}";

  @override
  RewindLines get streakKicker =>
      (you: "DEINE LÄNGSTE SERIE", me: "MEINE LÄNGSTE SERIE");

  @override
  String checkInsLabel(int count) =>
      count == 1 ? "Check-in\ndieses Jahr" : "Check-ins\ndieses Jahr";

  @override
  String ritualsContinuedLabel(int count) =>
      count == 1 ? "Ritual läuft\nweiter" : "Rituale laufen\nweiter";

  @override
  String get mostActiveMonthLabel => "Aktivster\nMonat";

  @override
  String streakLabel({
    required int streak,
    required int checkIns,
    required int month,
    required int continued,
  }) =>
      "Deine längste Ritualserie: ${number(streak)}. "
      "${_counted(checkIns, "Check-in", "Check-ins")} "
      "dieses Jahr, die meisten im ${monthName(month)}. "
      "${_counted(continued, "Ritual läuft", "Rituale laufen")} weiter.";

  @override
  RewindLines get mosaicSelf => (you: "DU", me: "ICH");

  @override
  String get familiarFace => "EIN BEKANNTES GESICHT";

  @override
  String mosaicMoments(int count) =>
      "IN ${_counted(count, "MOMENT", "MOMENTEN")}.";

  @override
  String get mosaicHint => "Tippen, zoomen, entdecken";

  @override
  RewindBadgeCopy badge(rust.RewindBadge badge) {
    final english = const EnglishRewindCopy().badge(badge);
    return (
      title: english.title,
      pronunciation: english.pronunciation,
      definition: switch (badge) {
        rust.RewindBadge.sunChaser =>
          "Jemand, der regelmäßig Sonnenaufgänge, Sonnenuntergänge und das Licht der goldenen Stunde fotografiert.",
        rust.RewindBadge.consistencyChamp =>
          "Jemand, der jeden einzelnen Monat zur Kamera gegriffen hat. Bei Wind und Wetter.",
        rust.RewindBadge.unpaidPhotographer =>
          "Der Grund, warum der Gruppenchat überhaupt Fotos hat.",
        rust.RewindBadge.mainCharacter =>
          "Jemand, der liebend gern vor der Kamera steht. Ohne diesen Star wäre jede Szene nur halb so gut.",
        rust.RewindBadge.earlyBird =>
          "Jemand, der schon vor dem Wecker wach ist und unterwegs, bevor es voll wird.",
        rust.RewindBadge.nightOwl =>
          "Jemand, dessen Kamera ein reges Nachtleben hat.",
        rust.RewindBadge.weekendStar =>
          "Montag bis Freitag wird geprobt. Am Wochenende geht der Vorhang auf.",
        rust.RewindBadge.pawparazzi =>
          "Jemand, dessen Haustier mehr Fotoshootings hatte als die meisten Promis.",
        rust.RewindBadge.foodie =>
          "Jemand, bei dem das Handy immer zuerst isst.",
        rust.RewindBadge.plantParent =>
          "Jemand, der für jede Blüte stehen bleibt und jedem Blatt Hallo sagt.",
        rust.RewindBadge.buildingBuff =>
          "Jemand, der Kunst in Bögen, Treppen und Skylines sieht.",
        rust.RewindBadge.screenshotCollector =>
          "Das wandelnde Archiv für Belege, Rezepte und jeden Chat, der aufgehoben gehört.",
        rust.RewindBadge.hobbyHopper =>
          "In allem ein bisschen zu Hause, im Spaßhaben Weltklasse. Alle paar Monate eine neue Leidenschaft.",
        rust.RewindBadge.indoorKid =>
          "Jemand, der die Kunst der Gemütlichkeit perfektioniert hat. Die schönsten Momente gibt’s zu Hause, mit den Liebsten.",
        rust.RewindBadge.outOfOffice =>
          "Ständig auf Entdeckungstour, mit einem Koffer, der dieses Jahr kaum ausgepackt wurde.",
        rust.RewindBadge.fullThrottle =>
          "Jemand, für den „Stillsitzen“ ein Fremdwort ist. Ob Spiel, Wanderweg oder Ziellinie: immer mittendrin.",
        rust.RewindBadge.eventHopper =>
          "Der Mensch mit dem vollsten Kalender im ganzen Freundeskreis. Wo was los war: immer dabei.",
        rust.RewindBadge.alwaysRolling =>
          "Jemand, der mehr Videos dreht als Fotos macht. Jede Sekunde ist Gold wert.",
        rust.RewindBadge.fitCheck =>
          "Jemand, der kein gutes Outfit ungenutzt lässt. Jeder Look wird festgehalten.",
        rust.RewindBadge.artLover =>
          "Jemand, der überall Kunst findet, von der Galerie bis zur Straßenecke.",
        rust.RewindBadge.limitedEdition =>
          "Jemand, der nicht alles knipst, nur die echten Highlights.",
        rust.RewindBadge.happySnapper =>
          "Jemand, der einfach alles fotografiert, weil alles ein Foto wert ist.",
        rust.RewindBadge.openingCredits =>
          "Jemand, dessen Geschichte gerade erst beginnt. Wenn das schon die Eröffnungsszene ist, wird der Rest episch.",
        rust.RewindBadge.guestStar =>
          "Jemand, der die Kamera für die Momente aufhebt, die zählen, und dann alles gibt.",
        rust.RewindBadge.mixedBag =>
          "Passt in keine Schublade, und genau das ist das Beste daran.",
      },
    );
  }

  @override
  String badgePronunciation(String pronunciation) => "$pronunciation · Subst.";

  @override
  String get badgeHeading => "WAS MEINE FOTOS\nÜBER MICH SAGEN";

  @override
  String get badgeHeadingLabel => "Was meine Fotos über mich sagen";

  @override
  String badgeLabel(String title) => "Abzeichen $title";

  @override
  String get badgeHint => "Zum erneuten Umdrehen doppeltippen";

  @override
  String get scrapbookPhotos => "Geknipste Fotos";

  @override
  String get scrapbookColour => "Farbe des Jahres";

  @override
  String get scrapbookPeople => "Lieblingsmenschen";

  @override
  String get scrapbookPlaces => "Lieblingsorte";

  @override
  String get scrapbookTop => "TOP";

  @override
  String get finaleTop => "WAS EIN";

  @override
  String get finaleBottom => "JAHR!";

  @override
  String get finaleLabel => "Was ein Jahr!";

  @override
  String get saveVideo => "Video speichern";

  @override
  String get savedVideo => "Gespeichert";

  @override
  String get shareRewind => "Rewind teilen";

  @override
  String get endCardTagline => "Dein Jahr im\nRückblick mit";

  @override
  String get videoTitle => "DEIN VIDEO ENTSTEHT";

  @override
  List<String> get videoQuips => const [
    "Spule das Band zurück",
    "Suche deine besten Seiten aus",
    "Bringe Ducky das Schneiden bei",
    "Lege den Soundtrack drunter",
    "Poliere jedes Bild",
    "Lasse den Abspann laufen",
  ];

  @override
  String get videoPreparing => "Bereite deine Fotos vor";

  @override
  String get videoWrapped => "Das ist im Kasten!";

  @override
  String get videoDone => "Alles fertig";

  @override
  String get videoAlmostDone => "Fast geschafft";

  @override
  String get videoKeepOpen => "Lass Ente geöffnet, das dauert nicht lange";

  @override
  String get cancel => "Abbrechen";

  @override
  String get alreadySaved => "Bereits gespeichert";

  @override
  String get backingUp => "Wird in Ente gesichert";

  @override
  String get savedAndBackingUp =>
      "In deiner Galerie gespeichert, wird in Ente gesichert";
}

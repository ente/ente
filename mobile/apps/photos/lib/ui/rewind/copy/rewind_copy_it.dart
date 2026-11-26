import "package:intl/intl.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/copy/rewind_city_names.dart";
import "package:photos/ui/rewind/copy/rewind_copy.dart";
import "package:photos/ui/rewind/copy/rewind_copy_en.dart";

final _decimal = NumberFormat.decimalPattern("it");

const _months = [
  "gennaio",
  "febbraio",
  "marzo",
  "aprile",
  "maggio",
  "giugno",
  "luglio",
  "agosto",
  "settembre",
  "ottobre",
  "novembre",
  "dicembre",
];

const _shortMonths = [
  "GEN",
  "FEB",
  "MAR",
  "APR",
  "MAG",
  "GIU",
  "LUG",
  "AGO",
  "SET",
  "OTT",
  "NOV",
  "DIC",
];

const _weekdays = [
  "lunedì",
  "martedì",
  "mercoledì",
  "giovedì",
  "venerdì",
  "sabato",
  "domenica",
];

String _capitalised(String word) =>
    "${word[0].toUpperCase()}${word.substring(1)}";

bool _elides(int value) =>
    value == 1 || value == 8 || value == 11 || (value >= 80 && value < 90);

String _percentOf(int percent) => "${_elides(percent) ? "l’" : "il "}$percent%";

class ItalianRewindCopy extends RewindCopy {
  const ItalianRewindCopy();

  String _counted(int value, String one, String many) =>
      "${number(value)} ${value == 1 ? one : many}";

  @override
  String number(int value) => _decimal
      .format(value)
      .replaceAll("\u202F", " ")
      .replaceAll("\u00A0", " ");

  @override
  String photoTally(String number, int count) => "$number ${photoUnit(count)}";

  @override
  String photoUnit(int count) => "foto";

  @override
  Map<String, String> get cityNames => italianCityNames;

  @override
  String shortDate(int day, int month, int year) =>
      "$day ${_shortMonths[month - 1]} $year";

  @override
  String monthBanner(int month) => _months[month - 1].toUpperCase();

  @override
  String monthName(int month) => _capitalised(_months[month - 1]);

  @override
  String get close => "Chiudi";

  @override
  String get playMusic => "Attiva la musica";

  @override
  String get muteMusic => "Disattiva la musica";

  @override
  String get share => "Condividi";

  @override
  String get shareVideo => "Condividi il video";

  @override
  String get nextCard => "Scheda successiva";

  @override
  String pageOf(int page, int count) => "Pagina $page di $count";

  @override
  String get dismiss => "Nascondi";

  @override
  String get watch => "Guarda";

  @override
  String get watchAgain => "Riguarda";

  @override
  String get resume => "Continua";

  @override
  String get newStatus => "Nuovo";

  @override
  String get newSticker => "NUOVO";

  @override
  String progress(int page, int count) => "$page di $count";

  @override
  String get readyTitle => "Il tuo Rewind ${RewindEdition.year} è pronto";

  @override
  String get readyBody => "Il tuo anno in foto. Pronto quando vuoi tu.";

  @override
  String get newCardsTitle =>
      "Il tuo Rewind ${RewindEdition.year} ha nuove schede";

  @override
  String get newCardsBody => "Riaprilo per scoprire le novità.";

  @override
  RewindLines get coverTagline =>
      (you: "IL TUO ANNO IN FOTO", me: "IL MIO ANNO IN FOTO");

  @override
  String get tapToStart => "Tocca per iniziare";

  @override
  RewindSetupLines setup(RewindSetup setup) => switch (setup) {
    RewindSetup.palette => (
      headlines: ["IL TUO ANNO\nHA UN COLORE"],
      callout: "TI DONA\nUN SACCO!",
    ),
    RewindSetup.places => (
      headlines: ["NE HAI FATTA\nDI STRADA."],
      callout: "LA FOTOCAMERA\nÈ VENUTA CON TE.",
    ),
    RewindSetup.people => (
      headlines: ["ALCUNI VOLTI\nCONTINUAVANO\nA SPUNTARE."],
      callout: "TIPO, TANTISSIMO!",
    ),
    RewindSetup.busiestDay => (
      headlines: ["UN GIORNO,\nNON SMETTEVI\nDI SCATTARE."],
      callout: "CLIC! CLIC! CLIC!",
    ),
    RewindSetup.newFaces => (
      headlines: ["IL CAST SI È\nALLARGATO"],
      callout: "PIÙ SIAMO, MEGLIO È!",
    ),
    RewindSetup.favourites => (
      headlines: ["IL MEGLIO\nDEL MEGLIO."],
      callout: "MERITANO UNA STELLA!",
    ),
    RewindSetup.ritual => (
      headlines: ["IN CERTE COSE\nERI UN OROLOGIO", "SVIZZERO."],
      callout: "È QUASI ORA!",
    ),
    RewindSetup.ritualStreak => (
      headlines: ["HAI CREATO\nDEI RITUALI."],
      callout: "UNA FOTO AL GIORNO.",
    ),
    RewindSetup.likes => (
      headlines: ["IL TUO FEED\nERA DI FUOCO!"],
      callout: "SOPRATTUTTO QUESTA!",
    ),
    RewindSetup.mosaic => (
      headlines: ["TUTTO\nTORNA."],
      callout: "FOTO DOPO FOTO.",
    ),
    RewindSetup.badge => (
      headlines: ["DOPO UN ANNO\nCOSÌ…"],
      callout: "TI MERITI UN BADGE!",
    ),
  };

  @override
  String tunnelAgo(int days) =>
      days < 1 ? "OGGI" : "${_counted(days, "GIORNO", "GIORNI")} FA";

  @override
  String get tunnelStartTitle => "SI PARTE DA QUI";

  @override
  RewindLines get tunnelStartBody =>
      (you: "La tua prima foto dell’anno.", me: "La mia prima foto dell’anno.");

  @override
  String get tunnelGoOnHint => "TOCCA O SCORRI IN SU PER CONTINUARE";

  @override
  String get tunnelFlyBackHint => "SCORRI IN GIÙ PER VOLARE INDIETRO";

  @override
  String tunnelMomentEyebrow(DateTime day) =>
      "${day.weekday == DateTime.sunday ? "UNA" : "UN"} "
      "${_weekdays[day.weekday - 1].toUpperCase()} "
      "DI ${monthBanner(day.month)}";

  @override
  String get tunnelMomentTitle => "TE LO RICORDI?";

  @override
  RewindLines get tunnelMomentBody =>
      (you: "Un momento del tuo anno.", me: "Un momento del mio anno.");

  @override
  String get tunnelLoading => "CARICO LA CASSETTA";

  @override
  String get tunnelFlyAgain => "VOLA ANCORA";

  @override
  RewindLines get photosCountKicker => (
    you: "NEL ${RewindEdition.year} HAI SCATTATO",
    me: "NEL ${RewindEdition.year} HO SCATTATO",
  );

  @override
  String memoriesUnit(int count) => count == 1 ? "ricordo" : "ricordi";

  @override
  RewindLines get topPercentKicker =>
      (you: "SU ENTE SEI NEL", me: "SU ENTE SONO NEL");

  @override
  String topPercent(int percent) => "TOP $percent%";

  @override
  String memoriesSaved(int count) =>
      "${_counted(count, "ricordo salvato", "ricordi salvati")}, "
      "e non è finita qui!";

  @override
  String get placesQuestion => "DOVE HAI SCATTATO DI PIÙ?";

  @override
  String get placesHint => "Tocca un francobollo per indovinare.";

  @override
  String placesPicked(String city) => "$city? Controlliamo\ni timbri postali.";

  @override
  RewindLines placesHeading({required bool travelled}) => travelled
      ? (you: "LE TUE FOTO HANNO VIAGGIATO", me: "LE MIE FOTO HANNO VIAGGIATO")
      : (you: "IL TUO POSTO N. 1", me: "IL MIO POSTO N. 1");

  @override
  String distance(int km) => "${number(km)} KM";

  @override
  String placesWon(String city, int photos) =>
      "$city ha vinto con ${this.photos(photos)}.";

  @override
  String placesNext(List<String> cities) => switch (cities) {
    [final next] => "Segue $next.",
    [final first, final second, ...] => "Seguono $first e $second.",
    _ => "",
  };

  @override
  String placesPlaced(String city, int place) =>
      "$city ha chiuso al ${place == 2 ? "secondo" : "terzo"} posto.";

  @override
  String placesHad(String city, int photos) =>
      "$city ne aveva ${number(photos)}.";

  @override
  RewindLines get globeKicker =>
      (you: "LE TUE FOTO HANNO VOLATO", me: "LE MIE FOTO HANNO VOLATO");

  @override
  String globeLaps(double laps) =>
      "Come fare ${laps.toStringAsFixed(1).replaceFirst(".", ",")} volte "
      "il giro del mondo.";

  @override
  String globeLapShare(int percent) =>
      "Come fare ${_percentOf(percent)} del giro del mondo.";

  @override
  String get globeHint => "TRASCINA PER RUOTARE";

  @override
  String globeLabel(int km, String laps) =>
      "Le tue foto hanno volato per ${number(km)} chilometri. $laps";

  @override
  String globeTally(int cities, int countries) =>
      "${_counted(cities, "CITTÀ", "CITTÀ")}"
      "  ·  "
      "${_counted(countries, "PAESE", "PAESI")}";

  @override
  String get raceQuestion => "CHI SPUNTA PIÙ SPESSO?";

  @override
  String get raceHint => "Tocca un volto per indovinare.";

  @override
  String racePicked(String name) => "$name? mossa audace";

  @override
  String raceOvertakes(String passer, String passed) =>
      "$passer SUPERA $passed!";

  @override
  String raceWinner(String name) => "$name SPUNTA PIÙ DI TUTTI!";

  @override
  RewindLines get raceCalledIt => (you: "CI HAI PRESO!", me: "CI HO PRESO!");

  @override
  String get raceClose => "MANCATO DI POCO!";

  @override
  String get raceMissed => "NON QUEST’ANNO!";

  @override
  RewindLines get racePick => (you: "SCELTA TUA", me: "SCELTA MIA");

  @override
  RewindLines boothBilling(int place) => switch (place) {
    0 => (you: "IL TUO N. 1", me: "IL MIO N. 1"),
    1 => (you: "SEMPRE AL TUO FIANCO", me: "SEMPRE AL MIO FIANCO"),
    _ => (
      you: "IL ${RewindEdition.year} È STATO PIÙ BELLO CON",
      me: "IL ${RewindEdition.year} È STATO PIÙ BELLO CON",
    ),
  };

  @override
  String boothPhotos(int count) => "${photos(count)} quest’anno!";

  @override
  RewindLines busiestDayKicker(int day, int month) {
    final monthWord = _months[month - 1];
    final onDay = switch (day) {
      1 => "Il primo $monthWord",
      8 || 11 => "L’$day $monthWord",
      _ => "Il $day $monthWord",
    };
    return (you: "$onDay hai scattato", me: "$onDay ho scattato");
  }

  @override
  String get busiestDayLine => "Una giornata da ricordare!";

  @override
  String newFacesTitle(int count) =>
      count == 1 ? "1 NUOVO VOLTO" : "${number(count)} NUOVI VOLTI";

  @override
  RewindLines newFacesLine(int count) {
    final debuted = count == 1 ? "ha debuttato" : "hanno debuttato";
    return (
      you: "$debuted nella tua galleria quest’anno.",
      me: "$debuted nella mia galleria quest’anno.",
    );
  }

  @override
  String colourName(rust.RewindColour colour) => switch (colour) {
    rust.RewindColour.cherryBomb => "AMARENA",
    rust.RewindColour.tangerinePop => "ARANCIATA",
    rust.RewindColour.lemonDrop => "GRANITA LIMONE",
    rust.RewindColour.pistachio => "PISTACCHIO",
    rust.RewindColour.berryBlue => "BLU MIRTILLO",
    rust.RewindColour.lavenderFizz => "VIOLETTA",
    rust.RewindColour.bubblegum => "ZUCCHERO FILATO",
    rust.RewindColour.hotCocoa => "CIOCCOLATA CALDA",
    rust.RewindColour.marshmallow => "PANNA MONTATA",
    rust.RewindColour.midnightCola => "LIQUIRIZIA",
  };

  String _colourWord(rust.RewindColour colour) => switch (colour) {
    rust.RewindColour.cherryBomb => "rosse",
    rust.RewindColour.tangerinePop => "arancioni",
    rust.RewindColour.lemonDrop => "gialle",
    rust.RewindColour.pistachio => "verdi",
    rust.RewindColour.berryBlue => "blu",
    rust.RewindColour.lavenderFizz => "viola",
    rust.RewindColour.bubblegum => "rosa",
    rust.RewindColour.hotCocoa => "marroni",
    rust.RewindColour.marshmallow => "bianche",
    rust.RewindColour.midnightCola => "nere",
  };

  @override
  RewindLines colourLine(int percent, rust.RewindColour colour) {
    final share = _capitalised(_percentOf(percent));
    final tint = _colourWord(colour);
    return (
      you: "$share delle tue foto erano soprattutto $tint.",
      me: "$share delle mie foto erano soprattutto $tint.",
    );
  }

  @override
  String get favouritesTitle => "I TUOI PREFERITI";

  @override
  String get myFavouritesTitle => "I MIEI PREFERITI";

  @override
  String get myFavouriteTitle => "IL MIO PREFERITO";

  @override
  String get favouritesLine => "Ricordi da custodire.";

  @override
  String get favouriteLine => "Un ricordo da custodire.";

  @override
  String get favouritesLabel => "I tuoi preferiti. $favouritesLine";

  @override
  RewindLines get habitKicker =>
      (you: "IL TUO RITUALE SETTIMANALE", me: "IL MIO RITUALE SETTIMANALE");

  @override
  String clockHour(int hour) => "${hour.toString().padLeft(2, "0")}:00";

  @override
  String habitTitle(int weekday, int hour) {
    final time = switch (hour) {
      0 => "a mezzanotte",
      1 => "all’una",
      _ => "alle $hour",
    };
    return "${weekday == DateTime.sunday ? "La" : "Il"} "
        "${_weekdays[weekday - 1]} $time";
  }

  @override
  RewindLines habitLine(int percent, int weekday) {
    final share = _percentOf(percent);
    final day = _weekdays[weekday - 1];
    return (
      you: "Hai scattato $share delle tue foto di $day.",
      me: "Ho scattato $share delle mie foto di $day.",
    );
  }

  @override
  String habitLabel(String title, String line) =>
      "Il tuo rituale settimanale: $title. $line";

  @override
  String weekdayInitial(int weekday) => _weekdays[weekday - 1][0].toUpperCase();

  @override
  String get crowdFavouriteTitle => "PREMIO DEL PUBBLICO";

  @override
  RewindLines get crowdFavouriteLine => (
    you: "La tua foto con più mi piace.",
    me: "La mia foto con più mi piace.",
  );

  @override
  String get crowdFavouriteLabel =>
      "Premio del pubblico. ${crowdFavouriteLine.you}";

  @override
  RewindLines get streakKicker =>
      (you: "LA TUA SERIE PIÙ LUNGA", me: "LA MIA SERIE PIÙ LUNGA");

  @override
  String checkInsLabel(int count) => "Check-in\nquest’anno";

  @override
  String ritualsContinuedLabel(int count) =>
      count == 1 ? "Rituale\nin corso" : "Rituali\nin corso";

  @override
  String get mostActiveMonthLabel => "Mese più\nattivo";

  @override
  String streakLabel({
    required int streak,
    required int checkIns,
    required int month,
    required int continued,
  }) {
    final monthWord = _months[month - 1];
    final inMonth = monthWord.startsWith("a")
        ? "ad $monthWord"
        : "a $monthWord";
    return "La tua serie di rituali più lunga: ${number(streak)}. "
        "${number(checkIns)} check-in quest’anno, "
        "la maggior parte $inMonth. "
        "${_counted(continued, "rituale", "rituali")} ancora in corso.";
  }

  @override
  RewindLines get mosaicSelf => (you: "TU", me: "IO");

  @override
  String get familiarFace => "UN VOLTO NOTO";

  @override
  String mosaicMoments(int count) =>
      "IN ${_counted(count, "MOMENTO", "MOMENTI")}.";

  @override
  String get mosaicHint => "Tocca o pizzica per esplorare";

  @override
  RewindBadgeCopy badge(rust.RewindBadge badge) {
    final english = const EnglishRewindCopy().badge(badge);
    return (
      title: english.title,
      pronunciation: english.pronunciation,
      definition: switch (badge) {
        rust.RewindBadge.sunChaser =>
          "Chi fotografa di continuo albe, tramonti e la luce dell’ora d’oro.",
        rust.RewindBadge.consistencyChamp =>
          "Chi non ha mai mancato l’appuntamento con il rullino, mese dopo mese. Con il bello e con il cattivo tempo.",
        rust.RewindBadge.unpaidPhotographer =>
          "Il motivo per cui nella chat di gruppo c’è anche solo una foto.",
        rust.RewindBadge.mainCharacter =>
          "Chi adora farsi fotografare. Ogni scena era più bella con la sua presenza.",
        rust.RewindBadge.earlyBird =>
          "Chi è in piedi prima della sveglia e in giro prima della folla.",
        rust.RewindBadge.nightOwl =>
          "Chi ha una fotocamera dalla vita notturna invidiabile.",
        rust.RewindBadge.weekendStar =>
          "Dal lunedì al venerdì si prova. Nel weekend si va in scena.",
        rust.RewindBadge.pawparazzi =>
          "Chi ha un amico a quattro zampe con più servizi fotografici di tante celebrità.",
        rust.RewindBadge.foodie =>
          "Chi lascia sempre il primo assaggio al telefono.",
        rust.RewindBadge.plantParent =>
          "Chi si ferma davanti a ogni fiore e saluta ogni foglia.",
        rust.RewindBadge.buildingBuff =>
          "Chi vede l’arte in archi, scalinate e skyline.",
        rust.RewindBadge.screenshotCollector =>
          "Custode di scontrini, ricette e di ogni chat che vale la pena ricordare.",
        rust.RewindBadge.hobbyHopper =>
          "Tuttofare del divertimento. Una nuova passione ogni paio di mesi.",
        rust.RewindBadge.indoorKid =>
          "Chi ha trasformato il calduccio di casa in un’arte. I momenti più belli si vivono lì, con le persone migliori.",
        rust.RewindBadge.outOfOffice =>
          "Giramondo la cui valigia quest’anno è stata disfatta a malapena.",
        rust.RewindBadge.fullThrottle =>
          "Chi non sa cosa voglia dire «stare a guardare». Una partita, un sentiero o un traguardo? Presente!",
        rust.RewindBadge.eventHopper =>
          "Chi ha l’agenda più invidiata del gruppo. Ovunque succedesse qualcosa, c’era.",
        rust.RewindBadge.alwaysRolling =>
          "Chi gira più video che foto. Ogni fotogramma non ha prezzo.",
        rust.RewindBadge.fitCheck =>
          "Chi non lascia mai un bell’outfit nell’armadio. Ogni look va immortalato.",
        rust.RewindBadge.artLover =>
          "Chi trova l’arte ovunque, dalle gallerie agli angoli di strada.",
        rust.RewindBadge.limitedEdition =>
          "Chi non fotografa tutto, solo il fior fiore.",
        rust.RewindBadge.happySnapper =>
          "Chi fotografa tutto, perché tutto ne vale la pena.",
        rust.RewindBadge.openingCredits =>
          "Chi ha una storia appena all’inizio. Se questa è la scena d’apertura, il seguito sarà epico.",
        rust.RewindBadge.guestStar =>
          "Chi tira fuori la fotocamera solo per i momenti che contano, e allora ci dà dentro.",
        rust.RewindBadge.mixedBag =>
          "Impossibile da etichettare, ed è proprio questo il bello.",
      },
    );
  }

  @override
  String badgePronunciation(String pronunciation) => "$pronunciation · sost.";

  @override
  String get badgeHeading => "COSA DICONO DI ME\nLE MIE FOTO";

  @override
  String get badgeHeadingLabel => "Cosa dicono di me le mie foto";

  @override
  String badgeLabel(String title) => "Badge $title";

  @override
  String get badgeHint => "Tocca due volte per girarlo di nuovo";

  @override
  String get scrapbookPhotos => "Foto scattate";

  @override
  String get scrapbookColour => "Colore dell’anno";

  @override
  String get scrapbookPeople => "Persone top";

  @override
  String get scrapbookPlaces => "Luoghi top";

  @override
  String get scrapbookTop => "TOP";

  @override
  String get finaleTop => "CHE";

  @override
  String get finaleBottom => "ANNO!";

  @override
  String get finaleLabel => "Che anno!";

  @override
  String get saveVideo => "Salva il video";

  @override
  String get savedVideo => "Salvato";

  @override
  String get shareRewind => "Condividi il tuo Rewind";

  @override
  String get endCardTagline => "Rivivi il tuo\nanno con";

  @override
  String get videoTitle => "PREPARO IL TUO VIDEO";

  @override
  List<String> get videoQuips => const [
    "Riavvolgo il nastro",
    "Cerco il tuo profilo migliore",
    "Insegno a Ducky a montare",
    "Aggiungo la colonna sonora",
    "Lucido ogni fotogramma",
    "Lancio i titoli di coda",
  ];

  @override
  String get videoPreparing => "Preparo le tue foto";

  @override
  String get videoWrapped => "Buona la prima!";

  @override
  String get videoDone => "Tutto fatto";

  @override
  String get videoAlmostDone => "Ci siamo quasi";

  @override
  String get videoKeepOpen => "Non chiudere Ente, ci vorrà poco";

  @override
  String get cancel => "Annulla";

  @override
  String get alreadySaved => "Già salvato";

  @override
  String get backingUp => "Backup su Ente in corso";

  @override
  String get savedAndBackingUp =>
      "Salvato nella tua galleria, backup su Ente in corso";
}

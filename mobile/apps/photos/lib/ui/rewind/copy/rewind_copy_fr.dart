import "package:intl/intl.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/copy/rewind_city_names.dart";
import "package:photos/ui/rewind/copy/rewind_copy.dart";
import "package:photos/ui/rewind/copy/rewind_copy_en.dart";

final _decimal = NumberFormat.decimalPattern("fr");

const _months = [
  "janvier",
  "février",
  "mars",
  "avril",
  "mai",
  "juin",
  "juillet",
  "août",
  "septembre",
  "octobre",
  "novembre",
  "décembre",
];

const _shortMonths = [
  "JANV",
  "FÉVR",
  "MARS",
  "AVR",
  "MAI",
  "JUIN",
  "JUIL",
  "AOÛT",
  "SEPT",
  "OCT",
  "NOV",
  "DÉC",
];

const _weekdays = [
  "lundi",
  "mardi",
  "mercredi",
  "jeudi",
  "vendredi",
  "samedi",
  "dimanche",
];

String _capitalised(String word) =>
    "${word[0].toUpperCase()}${word.substring(1)}";

String _ofMonth(int month) {
  final name = _months[month - 1];
  return "aeiou".contains(name[0]) ? "d’$name" : "de $name";
}

class FrenchRewindCopy extends RewindCopy {
  const FrenchRewindCopy();

  String _counted(int value, String one, String many) =>
      "${number(value)} ${value < 2 ? one : many}";

  @override
  String number(int value) =>
      _decimal.format(value).replaceAll("\u202F", "\u00A0");

  @override
  String photoTally(String number, int count) => "$number ${photoUnit(count)}";

  @override
  String photoUnit(int count) => count < 2 ? "photo" : "photos";

  @override
  Map<String, String> get cityNames => frenchCityNames;

  @override
  String shortDate(int day, int month, int year) =>
      "$day ${_shortMonths[month - 1]} $year";

  @override
  String monthBanner(int month) => _months[month - 1].toUpperCase();

  @override
  String monthName(int month) => _capitalised(_months[month - 1]);

  @override
  String get close => "Fermer";

  @override
  String get playMusic => "Lancer la musique";

  @override
  String get muteMusic => "Couper la musique";

  @override
  String get share => "Partager";

  @override
  String get shareVideo => "Partager la vidéo";

  @override
  String get nextCard => "Carte suivante";

  @override
  String pageOf(int page, int count) => "Page $page sur $count";

  @override
  String get dismiss => "Masquer";

  @override
  String get watch => "Regarder";

  @override
  String get watchAgain => "Revoir";

  @override
  String get resume => "Reprendre";

  @override
  String get newStatus => "Nouveau";

  @override
  String get newSticker => "NOUVEAU";

  @override
  String progress(int page, int count) => "$page sur $count";

  @override
  String get readyTitle => "Ton Rewind ${RewindEdition.year} est prêt";

  @override
  String get readyBody => "Ton année en photos. Quand tu veux.";

  @override
  String get newCardsTitle =>
      "Ton Rewind ${RewindEdition.year} a de nouvelles cartes";

  @override
  String get newCardsBody => "Rouvre-le pour découvrir les nouveautés.";

  @override
  RewindLines get coverTagline =>
      (you: "TON ANNÉE EN PHOTOS", me: "MON ANNÉE EN PHOTOS");

  @override
  String get tapToStart => "Appuie pour lancer";

  @override
  RewindSetupLines setup(RewindSetup setup) => switch (setup) {
    RewindSetup.palette => (
      headlines: ["TON ANNÉE\nA SA COULEUR"],
      callout: "ÇA TE VA\nÀ RAVIR !",
    ),
    RewindSetup.places => (
      headlines: ["TU AS VU\nDU PAYS."],
      callout: "L’APPAREIL\nÉTAIT DU VOYAGE.",
    ),
    RewindSetup.people => (
      headlines: ["DES VISAGES\nREVENAIENT\nSOUVENT."],
      callout: "GENRE, TRÈS SOUVENT !",
    ),
    RewindSetup.busiestDay => (
      headlines: ["UN JOUR, TU\nAS MITRAILLÉ\nSANS COMPTER."],
      callout: "ET ENCORE !",
    ),
    RewindSetup.newFaces => (
      headlines: ["LA TROUPE\nS’AGRANDIT"],
      callout: "BIENVENUE DANS LA BANDE !",
    ),
    RewindSetup.favourites => (
      headlines: ["LE MEILLEUR\nDU MEILLEUR."],
      callout: "ÇA MÉRITE UNE ÉTOILE !",
    ),
    RewindSetup.ritual => (
      headlines: ["CERTAINS TRUCS\nTOURNAIENT COMME", "UNE HORLOGE."],
      callout: "BIENTÔT L’HEURE !",
    ),
    RewindSetup.ritualStreak => (
      headlines: ["TU AS PRIS\nLE PLI."],
      callout: "UNE PHOTO PAR JOUR.",
    ),
    RewindSetup.likes => (
      headlines: ["TES PHOTOS\nONT CARTONNÉ !"],
      callout: "SURTOUT CELLE-LÀ.",
    ),
    RewindSetup.mosaic => (
      headlines: ["TOUT PREND\nFORME."],
      callout: "PHOTO APRÈS PHOTO.",
    ),
    RewindSetup.badge => (
      headlines: ["APRÈS UNE ANNÉE\nPAREILLE…"],
      callout: "TU MÉRITES UN BADGE !",
    ),
  };

  @override
  String tunnelAgo(int days) => days < 1
      ? "PLUS TÔT AUJOURD’HUI"
      : "IL Y A ${_counted(days, "JOUR", "JOURS")}";

  @override
  String get tunnelStartTitle => "TOUT COMMENCE ICI";

  @override
  RewindLines get tunnelStartBody => (
    you: "Ta première photo de l’année.",
    me: "Ma première photo de l’année.",
  );

  @override
  String get tunnelGoOnHint => "APPUIE OU GLISSE VERS LE HAUT POUR AVANCER";

  @override
  String get tunnelFlyBackHint => "GLISSE VERS LE BAS POUR REBROUSSER CHEMIN";

  @override
  String tunnelMomentEyebrow(DateTime day) =>
      "UN ${_weekdays[day.weekday - 1]} ${_ofMonth(day.month)}".toUpperCase();

  @override
  String get tunnelMomentTitle => "TU TE SOUVIENS ?";

  @override
  RewindLines get tunnelMomentBody =>
      (you: "Un moment de ton année.", me: "Un moment de mon année.");

  @override
  String get tunnelLoading => "ON CHARGE LA CASSETTE";

  @override
  String get tunnelFlyAgain => "ON REMET ÇA";

  @override
  RewindLines get photosCountKicker => (
    you: "EN ${RewindEdition.year}, TU AS IMMORTALISÉ",
    me: "EN ${RewindEdition.year}, J’AI IMMORTALISÉ",
  );

  @override
  String memoriesUnit(int count) => count < 2 ? "souvenir" : "souvenirs";

  @override
  RewindLines get topPercentKicker =>
      (you: "SUR ENTE, TU ES DANS LE", me: "SUR ENTE, JE SUIS DANS LE");

  @override
  String topPercent(int percent) => "TOP $percent%";

  @override
  String memoriesSaved(int count) =>
      "${_counted(count, "souvenir sauvegardé", "souvenirs sauvegardés")}, "
      "et ce n’est pas fini !";

  @override
  String get placesQuestion => "OÙ AS-TU LE PLUS PHOTOGRAPHIÉ ?";

  @override
  String get placesHint => "Appuie sur un timbre pour deviner.";

  @override
  String placesPicked(String city) =>
      "$city ? Le cachet\nde la poste fera foi.";

  @override
  RewindLines placesHeading({required bool travelled}) => travelled
      ? (you: "TES PHOTOS ONT VOYAGÉ", me: "MES PHOTOS ONT VOYAGÉ")
      : (you: "TON LIEU PHARE", me: "MON LIEU PHARE");

  @override
  String distance(int km) => "${number(km)} KM";

  @override
  String placesWon(String city, int photos) =>
      "$city l’emporte avec ${this.photos(photos)}.";

  @override
  String placesNext(List<String> cities) => switch (cities) {
    [final next] => "$next termine deuxième.",
    [final first, final second, ...] =>
      "$first et $second complètent le podium.",
    _ => "",
  };

  @override
  String placesPlaced(String city, int place) =>
      "$city termine ${place == 2 ? "deuxième" : "troisième"}.";

  @override
  String placesHad(String city, int photos) =>
      "$city en compte ${number(photos)}.";

  @override
  RewindLines get globeKicker =>
      (you: "TES PHOTOS ONT PARCOURU", me: "MES PHOTOS ONT PARCOURU");

  @override
  String globeLaps(double laps) =>
      "Soit ${laps.toStringAsFixed(1).replaceFirst(".", ",")} fois "
      "le tour du monde.";

  @override
  String globeLapShare(int percent) => "Soit $percent% d’un tour du monde.";

  @override
  String get globeHint => "GLISSE POUR FAIRE TOURNER";

  @override
  String globeLabel(int km, String laps) =>
      "Tes photos ont parcouru ${number(km)} kilomètres. $laps";

  @override
  String globeTally(int cities, int countries) =>
      "${_counted(cities, "VILLE", "VILLES")}"
      "  ·  "
      "${_counted(countries, "PAYS", "PAYS")}";

  @override
  String get raceQuestion => "QUI APPARAÎT LE PLUS ?";

  @override
  String get raceHint => "Appuie sur un visage pour deviner.";

  @override
  String racePicked(String name) => "$name ? pari osé";

  @override
  String raceOvertakes(String passer, String passed) =>
      "$passer DÉPASSE $passed !";

  @override
  String raceWinner(String name) => "$name ARRIVE EN TÊTE !";

  @override
  RewindLines get raceCalledIt => (you: "BIEN VU !", me: "J’AVAIS VU JUSTE !");

  @override
  String get raceClose => "PAS LOIN !";

  @override
  String get raceMissed => "PAS CETTE ANNÉE !";

  @override
  RewindLines get racePick => (you: "TON PARI", me: "MON PARI");

  @override
  RewindLines boothBilling(int place) => switch (place) {
    0 => (you: "TON NUMÉRO 1", me: "MON NUMÉRO 1"),
    1 => (you: "TOUJOURS À TES CÔTÉS", me: "TOUJOURS À MES CÔTÉS"),
    _ => (
      you: "${RewindEdition.year}, C’ÉTAIT MIEUX AVEC",
      me: "${RewindEdition.year}, C’ÉTAIT MIEUX AVEC",
    ),
  };

  @override
  String boothPhotos(int count) => "${photos(count)} cette année !";

  @override
  RewindLines busiestDayKicker(int day, int month) {
    final onDay = "Le ${day == 1 ? "1er" : "$day"} ${_months[month - 1]}";
    return (you: "$onDay, tu as pris", me: "$onDay, j’ai pris");
  }

  @override
  String get busiestDayLine => "Mémorable, cette journée !";

  @override
  String newFacesTitle(int count) =>
      count == 1 ? "1 NOUVEAU VISAGE" : "${number(count)} NOUVEAUX VISAGES";

  @override
  RewindLines newFacesLine(int count) {
    final joined = count == 1 ? "a rejoint" : "ont rejoint";
    return (
      you: "$joined ta galerie cette année.",
      me: "$joined ma galerie cette année.",
    );
  }

  @override
  String colourName(rust.RewindColour colour) => switch (colour) {
    rust.RewindColour.cherryBomb => "BOMBE CERISE",
    rust.RewindColour.tangerinePop => "MANDARINE POP",
    rust.RewindColour.lemonDrop => "CITRON ACIDULÉ",
    rust.RewindColour.pistachio => "PISTACHE",
    rust.RewindColour.berryBlue => "MYRTILLE",
    rust.RewindColour.lavenderFizz => "SODA LAVANDE",
    rust.RewindColour.bubblegum => "BUBBLE-GUM",
    rust.RewindColour.hotCocoa => "CHOCOLAT CHAUD",
    rust.RewindColour.marshmallow => "GUIMAUVE",
    rust.RewindColour.midnightCola => "RÉGLISSE",
  };

  String _colourWord(rust.RewindColour colour) => switch (colour) {
    rust.RewindColour.cherryBomb => "rouges",
    rust.RewindColour.tangerinePop => "orange",
    rust.RewindColour.lemonDrop => "jaunes",
    rust.RewindColour.pistachio => "vertes",
    rust.RewindColour.berryBlue => "bleues",
    rust.RewindColour.lavenderFizz => "violettes",
    rust.RewindColour.bubblegum => "roses",
    rust.RewindColour.hotCocoa => "marron",
    rust.RewindColour.marshmallow => "blanches",
    rust.RewindColour.midnightCola => "noires",
  };

  @override
  RewindLines colourLine(int percent, rust.RewindColour colour) => (
    you: "$percent% de tes photos étaient surtout ${_colourWord(colour)}.",
    me: "$percent% de mes photos étaient surtout ${_colourWord(colour)}.",
  );

  @override
  String get favouritesTitle => "TES FAVORIS";

  @override
  String get myFavouritesTitle => "MES FAVORIS";

  @override
  String get myFavouriteTitle => "MON FAVORI";

  @override
  String get favouritesLine => "Des souvenirs à chérir.";

  @override
  String get favouriteLine => "Un souvenir à chérir.";

  @override
  String get favouritesLabel => "Tes favoris. $favouritesLine";

  @override
  RewindLines get habitKicker =>
      (you: "TON RITUEL HEBDOMADAIRE", me: "MON RITUEL HEBDOMADAIRE");

  @override
  String clockHour(int hour) => "${hour.toString().padLeft(2, "0")}:00";

  @override
  String habitTitle(int weekday, int hour) =>
      "Le ${_weekdays[weekday - 1]} à $hour h";

  @override
  RewindLines habitLine(int percent, int weekday) => (
    you: "Tu as pris $percent% de tes photos le ${_weekdays[weekday - 1]}.",
    me: "J’ai pris $percent% de mes photos le ${_weekdays[weekday - 1]}.",
  );

  @override
  String habitLabel(String title, String line) =>
      "Ton rituel hebdomadaire : $title. $line";

  @override
  String weekdayInitial(int weekday) => _weekdays[weekday - 1][0].toUpperCase();

  @override
  String get crowdFavouriteTitle => "COUP DE CŒUR DU PUBLIC";

  @override
  RewindLines get crowdFavouriteLine =>
      (you: "Ta photo la plus aimée.", me: "Ma photo la plus aimée.");

  @override
  String get crowdFavouriteLabel =>
      "Coup de cœur du public. ${crowdFavouriteLine.you}";

  @override
  RewindLines get streakKicker =>
      (you: "TA PLUS LONGUE SÉRIE", me: "MA PLUS LONGUE SÉRIE");

  @override
  String checkInsLabel(int count) =>
      count < 2 ? "Check-in\ncette année" : "Check-ins\ncette année";

  @override
  String ritualsContinuedLabel(int count) =>
      count < 2 ? "Routine\nen cours" : "Routines\nen cours";

  @override
  String get mostActiveMonthLabel => "Mois le plus\nactif";

  @override
  String streakLabel({
    required int streak,
    required int checkIns,
    required int month,
    required int continued,
  }) =>
      "Ta plus longue série de routine : ${number(streak)}. "
      "${_counted(checkIns, "check-in", "check-ins")} "
      "cette année, surtout en ${_months[month - 1]}. "
      "${_counted(continued, "routine", "routines")} toujours en cours.";

  @override
  RewindLines get mosaicSelf => (you: "TOI", me: "MOI");

  @override
  String get familiarFace => "UN VISAGE FAMILIER";

  @override
  String mosaicMoments(int count) =>
      "EN ${_counted(count, "MOMENT", "MOMENTS")}.";

  @override
  String get mosaicHint => "Appuie ou zoome pour explorer";

  @override
  RewindBadgeCopy badge(rust.RewindBadge badge) {
    final english = const EnglishRewindCopy().badge(badge);
    return (
      title: english.title,
      pronunciation: english.pronunciation,
      definition: switch (badge) {
        rust.RewindBadge.sunChaser =>
          "Personne qui photographie régulièrement levers et couchers de soleil, et la lumière de l’heure dorée.",
        rust.RewindBadge.consistencyChamp =>
          "Personne qui n’a jamais fait faux bond à sa pellicule, pas un seul mois. Qu’il pleuve ou qu’il vente.",
        rust.RewindBadge.unpaidPhotographer =>
          "Sans cette personne, la conversation de groupe n’aurait pas une seule photo.",
        rust.RewindBadge.mainCharacter =>
          "Personne qui adore poser devant l’objectif. Sa présence embellissait chaque scène.",
        rust.RewindBadge.earlyBird =>
          "Personne qui est debout avant le réveil et dehors avant la foule.",
        rust.RewindBadge.nightOwl =>
          "Personne dont l’appareil photo mène une vie nocturne trépidante.",
        rust.RewindBadge.weekendStar =>
          "Du lundi au vendredi, on répète. Le week-end, place au spectacle.",
        rust.RewindBadge.pawparazzi =>
          "Personne dont l’animal a fait plus de séances photo que bien des stars.",
        rust.RewindBadge.foodie =>
          "Personne dont le téléphone mange toujours en premier.",
        rust.RewindBadge.plantParent =>
          "Personne qui s’arrête devant chaque fleur et dit bonjour à chaque feuille.",
        rust.RewindBadge.buildingBuff =>
          "Personne qui voit de l’art dans les arches, les escaliers et les silhouettes des villes.",
        rust.RewindBadge.screenshotCollector =>
          "Archiviste des tickets de caisse, des recettes et de chaque conversation à ne pas oublier.",
        rust.RewindBadge.hobbyHopper =>
          "Touche-à-tout, pro du fun. Une nouvelle passion à chaque saison.",
        rust.RewindBadge.indoorKid =>
          "Personne qui a fait du cocooning un art. Les plus beaux moments se vivent à la maison, en très bonne compagnie.",
        rust.RewindBadge.outOfOffice =>
          "Âme voyageuse qui n’a presque jamais défait sa valise cette année.",
        rust.RewindBadge.fullThrottle =>
          "Personne qui ne tient pas en place. Un match, un sentier ou une ligne d’arrivée ? Toujours de la partie.",
        rust.RewindBadge.eventHopper =>
          "L’agenda le mieux rempli de la bande. S’il se passait quelque chose, présence garantie.",
        rust.RewindBadge.alwaysRolling =>
          "Personne qui tourne plus de vidéos que de photos. Chaque plan n’a pas de prix.",
        rust.RewindBadge.fitCheck =>
          "Personne qui ne laisse jamais une belle tenue passer inaperçue. Chaque look est immortalisé.",
        rust.RewindBadge.artLover =>
          "Personne qui trouve de l’art partout, des galeries aux coins de rue.",
        rust.RewindBadge.limitedEdition =>
          "Personne qui ne photographie pas tout, seulement la crème de la crème.",
        rust.RewindBadge.happySnapper =>
          "Personne qui photographie tout, parce que tout en vaut la peine.",
        rust.RewindBadge.openingCredits =>
          "Personne dont l’histoire ne fait que commencer. Si c’est la scène d’ouverture, la suite s’annonce épique.",
        rust.RewindBadge.guestStar =>
          "Personne qui garde son appareil pour les moments qui comptent, puis met le paquet.",
        rust.RewindBadge.mixedBag =>
          "Impossible à ranger dans une case, et c’est tout l’intérêt.",
      },
    );
  }

  @override
  String badgePronunciation(String pronunciation) => "$pronunciation · n.";

  @override
  String get badgeHeading => "CE QUE MES PHOTOS\nDISENT DE MOI";

  @override
  String get badgeHeadingLabel => "Ce que mes photos disent de moi";

  @override
  String badgeLabel(String title) => "Badge $title";

  @override
  String get badgeHint => "Appuie deux fois pour le retourner à nouveau";

  @override
  String get scrapbookPhotos => "Photos prises";

  @override
  String get scrapbookColour => "Couleur de l’année";

  @override
  String get scrapbookPeople => "Têtes d’affiche";

  @override
  String get scrapbookPlaces => "Lieux phares";

  @override
  String get scrapbookTop => "TOP";

  @override
  String get finaleTop => "QUELLE";

  @override
  String get finaleBottom => "ANNÉE !";

  @override
  String get finaleLabel => "Quelle année !";

  @override
  String get saveVideo => "Enregistrer la vidéo";

  @override
  String get savedVideo => "Enregistrée";

  @override
  String get shareRewind => "Partage ton Rewind";

  @override
  String get endCardTagline => "Retour sur\nton année avec";

  @override
  String get videoTitle => "ON MONTE TA VIDÉO";

  @override
  List<String> get videoQuips => const [
    "On rembobine la cassette",
    "On cherche ton meilleur profil",
    "On initie Ducky au montage",
    "On ajoute la bande-son",
    "On peaufine chaque image",
    "On déroule le générique",
  ];

  @override
  String get videoPreparing => "On prépare tes photos";

  @override
  String get videoWrapped => "C’est dans la boîte !";

  @override
  String get videoDone => "Tout est prêt";

  @override
  String get videoAlmostDone => "On y est presque";

  @override
  String get videoKeepOpen => "Laisse Ente ouvert, ça ne sera pas long";

  @override
  String get cancel => "Annuler";

  @override
  String get alreadySaved => "Vidéo déjà enregistrée";

  @override
  String get backingUp => "Sauvegarde sur Ente en cours";

  @override
  String get savedAndBackingUp =>
      "Enregistrée dans ta galerie, sauvegarde sur Ente en cours";
}

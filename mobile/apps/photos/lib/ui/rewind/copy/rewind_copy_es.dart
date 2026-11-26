import "package:intl/intl.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/copy/rewind_city_names.dart";
import "package:photos/ui/rewind/copy/rewind_copy.dart";
import "package:photos/ui/rewind/copy/rewind_copy_en.dart";

final _decimal = NumberFormat.decimalPattern("es");

final _unbreakableSpaces = RegExp("[  ]");

final _iSound = RegExp("^h?[ií](?![aeiouáéíóú])");

const _months = [
  "enero",
  "febrero",
  "marzo",
  "abril",
  "mayo",
  "junio",
  "julio",
  "agosto",
  "septiembre",
  "octubre",
  "noviembre",
  "diciembre",
];

const _shortMonths = [
  "ENE",
  "FEB",
  "MAR",
  "ABR",
  "MAY",
  "JUN",
  "JUL",
  "AGO",
  "SEP",
  "OCT",
  "NOV",
  "DIC",
];

const _weekdays = [
  "lunes",
  "martes",
  "miércoles",
  "jueves",
  "viernes",
  "sábado",
  "domingo",
];

const _weekdayPlurals = [
  "lunes",
  "martes",
  "miércoles",
  "jueves",
  "viernes",
  "sábados",
  "domingos",
];

String _capitalised(String word) =>
    "${word[0].toUpperCase()}${word.substring(1)}";

String _and(String first, String second) =>
    "$first ${_iSound.hasMatch(second.toLowerCase()) ? "e" : "y"} $second";

class SpanishRewindCopy extends RewindCopy {
  const SpanishRewindCopy();

  String _counted(int value, String one, String many) =>
      "${number(value)} ${value == 1 ? one : many}";

  @override
  String number(int value) =>
      _decimal.format(value).replaceAll(_unbreakableSpaces, " ");

  @override
  String photoTally(String number, int count) => "$number ${photoUnit(count)}";

  @override
  String photoUnit(int count) => count == 1 ? "foto" : "fotos";

  @override
  Map<String, String> get cityNames => spanishCityNames;

  @override
  String shortDate(int day, int month, int year) =>
      "$day ${_shortMonths[month - 1]} $year";

  @override
  String monthBanner(int month) => _months[month - 1].toUpperCase();

  @override
  String monthName(int month) => _capitalised(_months[month - 1]);

  @override
  String get close => "Cerrar";

  @override
  String get playMusic => "Reproducir música";

  @override
  String get muteMusic => "Silenciar música";

  @override
  String get share => "Compartir";

  @override
  String get shareVideo => "Compartir vídeo";

  @override
  String get nextCard => "Siguiente tarjeta";

  @override
  String pageOf(int page, int count) => "Página $page de $count";

  @override
  String get dismiss => "Descartar";

  @override
  String get watch => "Ver";

  @override
  String get watchAgain => "Volver a ver";

  @override
  String get resume => "Continuar";

  @override
  String get newStatus => "Nuevo";

  @override
  String get newSticker => "NUEVO";

  @override
  String progress(int page, int count) => "$page de $count";

  @override
  String get readyTitle => "Tu Rewind ${RewindEdition.year} ya está aquí";

  @override
  String get readyBody => "Tu año en fotos. Te espera cuando quieras.";

  @override
  String get newCardsTitle =>
      "Tu Rewind ${RewindEdition.year} tiene tarjetas nuevas";

  @override
  String get newCardsBody => "Ábrelo de nuevo para ver las novedades.";

  @override
  RewindLines get coverTagline =>
      (you: "TU AÑO EN FOTOS", me: "MI AÑO EN FOTOS");

  @override
  String get tapToStart => "Toca para empezar";

  @override
  RewindSetupLines setup(RewindSetup setup) => switch (setup) {
    RewindSetup.palette => (
      headlines: ["TU AÑO\nTUVO UN COLOR"],
      callout: "¡TE QUEDA\nGENIAL!",
    ),
    RewindSetup.places => (
      headlines: ["SALISTE\nA EXPLORAR."],
      callout: "Y LA CÁMARA\nTAMBIÉN.",
    ),
    RewindSetup.people => (
      headlines: ["ALGUNAS CARAS\nSE DEJABAN\nVER."],
      callout: "¡Y MUCHO!",
    ),
    RewindSetup.busiestDay => (
      headlines: ["UN DÍA,\nNO PARASTE DE\nSACAR FOTOS."],
      callout: "¡CLIC, CLIC, CLIC!",
    ),
    RewindSetup.newFaces => (
      headlines: ["EL ELENCO\nCRECIÓ"],
      callout: "¡YA SON FAMILIA!",
    ),
    RewindSetup.favourites => (
      headlines: ["LO MEJOR\nDE LO MEJOR."],
      callout: "¡MERECEN UNA ESTRELLA!",
    ),
    RewindSetup.ritual => (
      headlines: ["ALGUNAS COSAS\nIBAN COMO UN", "RELOJ SUIZO."],
      callout: "¡CASI ES LA HORA!",
    ),
    RewindSetup.ritualStreak => (
      headlines: ["CREASTE\nRITUALES."],
      callout: "UNA FOTO AL DÍA.",
    ),
    RewindSetup.likes => (
      headlines: ["¡TU FEED\nARRASÓ!"],
      callout: "¡SOBRE TODO ESTA!",
    ),
    RewindSetup.mosaic => (headlines: ["TODO\nSUMA."], callout: "FOTO A FOTO."),
    RewindSetup.badge => (
      headlines: ["DESPUÉS DE\nUN AÑO ASÍ…"],
      callout: "¡MERECES UNA INSIGNIA!",
    ),
  };

  @override
  String tunnelAgo(int days) =>
      days < 1 ? "HOY MISMO" : "HACE ${_counted(days, "DÍA", "DÍAS")}";

  @override
  String get tunnelStartTitle => "AQUÍ EMPEZÓ TODO";

  @override
  RewindLines get tunnelStartBody =>
      (you: "Tu primera foto del año.", me: "Mi primera foto del año.");

  @override
  String get tunnelGoOnHint => "TOCA O DESLIZA HACIA ARRIBA PARA SEGUIR";

  @override
  String get tunnelFlyBackHint => "DESLIZA HACIA ABAJO PARA VOLVER VOLANDO";

  @override
  String tunnelMomentEyebrow(DateTime day) =>
      "UN ${_weekdays[day.weekday - 1].toUpperCase()} "
      "DE ${monthBanner(day.month)}";

  @override
  String get tunnelMomentTitle => "¿TE ACUERDAS?";

  @override
  RewindLines get tunnelMomentBody =>
      (you: "Un momento de tu año.", me: "Un momento de mi año.");

  @override
  String get tunnelLoading => "CARGANDO LA CINTA";

  @override
  String get tunnelFlyAgain => "OTRA VUELTA";

  @override
  RewindLines get photosCountKicker => (
    you: "EN ${RewindEdition.year} CAPTURASTE",
    me: "EN ${RewindEdition.year} CAPTURÉ",
  );

  @override
  String memoriesUnit(int count) => count == 1 ? "recuerdo" : "recuerdos";

  @override
  RewindLines get topPercentKicker =>
      (you: "EN ENTE, ESTÁS EN EL", me: "EN ENTE, ESTOY EN EL");

  @override
  String topPercent(int percent) => "TOP $percent%";

  @override
  String memoriesSaved(int count) =>
      "${_counted(count, "recuerdo guardado", "recuerdos guardados")}, "
      "¡y sumando!";

  @override
  String get placesQuestion => "¿DÓNDE SACASTE MÁS FOTOS?";

  @override
  String get placesHint => "Toca un sello para adivinar.";

  @override
  String placesPicked(String city) =>
      "¿$city? Veamos qué\ndicen los matasellos.";

  @override
  RewindLines placesHeading({required bool travelled}) => travelled
      ? (you: "TUS FOTOS VIAJARON", me: "MIS FOTOS VIAJARON")
      : (you: "TU LUGAR ESTRELLA", me: "MI LUGAR ESTRELLA");

  @override
  String distance(int km) => "${number(km)} KM";

  @override
  String placesWon(String city, int photos) =>
      "$city ganó con ${this.photos(photos)}.";

  @override
  String placesNext(List<String> cities) => switch (cities) {
    [final next] => "Le siguió $next.",
    [final first, final second, ...] => "Le siguieron ${_and(first, second)}.",
    _ => "",
  };

  @override
  String placesPlaced(String city, int place) =>
      "$city quedó en ${place == 2 ? "segundo" : "tercer"} lugar.";

  @override
  String placesHad(String city, int photos) =>
      "$city se quedó en ${number(photos)}.";

  @override
  RewindLines get globeKicker =>
      (you: "TUS FOTOS VOLARON", me: "MIS FOTOS VOLARON");

  @override
  String globeLaps(double laps) =>
      "Eso son ${laps.toStringAsFixed(1).replaceFirst(".", ",")} vueltas "
      "al mundo.";

  @override
  String globeLapShare(int percent) =>
      "Eso es el $percent% de una vuelta al mundo.";

  @override
  String get globeHint => "ARRASTRA PARA GIRAR";

  @override
  String globeLabel(int km, String laps) =>
      "Tus fotos volaron ${number(km)} kilómetros. $laps";

  @override
  String globeTally(int cities, int countries) =>
      "${_counted(cities, "CIUDAD", "CIUDADES")}"
      "  ·  "
      "${_counted(countries, "PAÍS", "PAÍSES")}";

  @override
  String get raceQuestion => "¿QUIÉN SALIÓ MÁS EN LAS FOTOS?";

  @override
  String get raceHint => "Toca una cara para adivinar.";

  @override
  String racePicked(String name) => "¿$name? apuesta atrevida";

  @override
  String raceOvertakes(String passer, String passed) =>
      "¡$passer SUPERA A $passed!";

  @override
  String raceWinner(String name) => "¡$name SALIÓ MÁS QUE NADIE!";

  @override
  RewindLines get raceCalledIt =>
      (you: "¡DISTE EN EL CLAVO!", me: "¡DI EN EL CLAVO!");

  @override
  String get raceClose => "¡POR POCO!";

  @override
  String get raceMissed => "¡ESTE AÑO NO!";

  @override
  RewindLines get racePick => (you: "TU APUESTA", me: "MI APUESTA");

  @override
  RewindLines boothBilling(int place) => switch (place) {
    0 => (you: "TU NÚMERO 1", me: "MI NÚMERO 1"),
    1 => (you: "SIEMPRE A TU LADO", me: "SIEMPRE A MI LADO"),
    _ => (
      you: "${RewindEdition.year} FUE MEJOR CON",
      me: "${RewindEdition.year} FUE MEJOR CON",
    ),
  };

  @override
  String boothPhotos(int count) => "¡${photos(count)} este año!";

  @override
  RewindLines busiestDayKicker(int day, int month) {
    final onDay = "El $day de ${_months[month - 1]}";
    return (you: "$onDay sacaste", me: "$onDay saqué");
  }

  @override
  String get busiestDayLine => "¡Sin duda, un día para recordar!";

  @override
  String newFacesTitle(int count) =>
      count == 1 ? "1 CARA NUEVA" : "${number(count)} CARAS NUEVAS";

  @override
  RewindLines newFacesLine(int count) {
    final debuted = count == 1 ? "debutó" : "debutaron";
    return (
      you: "$debuted en tu galería este año.",
      me: "$debuted en mi galería este año.",
    );
  }

  @override
  String colourName(rust.RewindColour colour) => switch (colour) {
    rust.RewindColour.cherryBomb => "BOMBA DE CEREZA",
    rust.RewindColour.tangerinePop => "MANDARINA POP",
    rust.RewindColour.lemonDrop => "GOTA DE LIMÓN",
    rust.RewindColour.pistachio => "PISTACHO",
    rust.RewindColour.berryBlue => "AZUL ARÁNDANO",
    rust.RewindColour.lavenderFizz => "SODA DE LAVANDA",
    rust.RewindColour.bubblegum => "CHICLE",
    rust.RewindColour.hotCocoa => "CHOCOLATITO",
    rust.RewindColour.marshmallow => "MALVAVISCO",
    rust.RewindColour.midnightCola => "COLA NOCTURNA",
  };

  String _colourWord(rust.RewindColour colour) => switch (colour) {
    rust.RewindColour.cherryBomb => "rojo",
    rust.RewindColour.tangerinePop => "naranja",
    rust.RewindColour.lemonDrop => "amarillo",
    rust.RewindColour.pistachio => "verde",
    rust.RewindColour.berryBlue => "azul",
    rust.RewindColour.lavenderFizz => "morado",
    rust.RewindColour.bubblegum => "rosa",
    rust.RewindColour.hotCocoa => "marrón",
    rust.RewindColour.marshmallow => "blanco",
    rust.RewindColour.midnightCola => "negro",
  };

  @override
  RewindLines colourLine(int percent, rust.RewindColour colour) => (
    you: "En el $percent% de tus fotos dominaba el ${_colourWord(colour)}.",
    me: "En el $percent% de mis fotos dominaba el ${_colourWord(colour)}.",
  );

  @override
  String get favouritesTitle => "TUS FAVORITOS";

  @override
  String get myFavouritesTitle => "MIS FAVORITOS";

  @override
  String get myFavouriteTitle => "MI FOTO FAVORITA";

  @override
  String get favouritesLine => "Recuerdos para atesorar.";

  @override
  String get favouriteLine => "Un recuerdo para atesorar.";

  @override
  String get favouritesLabel => "Tus favoritos. $favouritesLine";

  @override
  RewindLines get habitKicker =>
      (you: "TU RITUAL SEMANAL", me: "MI RITUAL SEMANAL");

  @override
  String clockHour(int hour) => "${hour.toString().padLeft(2, "0")}:00";

  @override
  String habitTitle(int weekday, int hour) =>
      "${_capitalised(_weekdayPlurals[weekday - 1])}, ${clockHour(hour)}";

  @override
  RewindLines habitLine(int percent, int weekday) {
    final days = _weekdayPlurals[weekday - 1];
    return (
      you: "Sacaste el $percent% de tus fotos los $days.",
      me: "Saqué el $percent% de mis fotos los $days.",
    );
  }

  @override
  String habitLabel(String title, String line) =>
      "Tu ritual semanal: $title. $line";

  @override
  String weekdayInitial(int weekday) => _weekdays[weekday - 1][0].toUpperCase();

  @override
  String get crowdFavouriteTitle => "LA FAVORITA DEL PÚBLICO";

  @override
  RewindLines get crowdFavouriteLine =>
      (you: "Tu foto más popular.", me: "Mi foto más popular.");

  @override
  String get crowdFavouriteLabel =>
      "La favorita del público. ${crowdFavouriteLine.you}";

  @override
  RewindLines get streakKicker =>
      (you: "TU RACHA MÁS LARGA", me: "MI RACHA MÁS LARGA");

  @override
  String checkInsLabel(int count) =>
      count == 1 ? "Check-in\neste año" : "Check-ins\neste año";

  @override
  String ritualsContinuedLabel(int count) =>
      count == 1 ? "Ritual\nen marcha" : "Rituales\nen marcha";

  @override
  String get mostActiveMonthLabel => "Mes más\nactivo";

  @override
  String streakLabel({
    required int streak,
    required int checkIns,
    required int month,
    required int continued,
  }) =>
      "Tu racha de rituales más larga: ${number(streak)}. "
      "${_counted(checkIns, "check-in", "check-ins")} "
      "este año, sobre todo en ${_months[month - 1]}. "
      "${_counted(continued, "ritual sigue", "rituales siguen")} en marcha.";

  @override
  RewindLines get mosaicSelf => (you: "TÚ", me: "YO");

  @override
  String get familiarFace => "UNA CARA CONOCIDA";

  @override
  String mosaicMoments(int count) =>
      "EN ${_counted(count, "MOMENTO", "MOMENTOS")}.";

  @override
  String get mosaicHint => "Toca o haz zoom para explorar";

  @override
  RewindBadgeCopy badge(rust.RewindBadge badge) {
    final english = const EnglishRewindCopy().badge(badge);
    return (
      title: english.title,
      pronunciation: english.pronunciation,
      definition: switch (badge) {
        rust.RewindBadge.sunChaser =>
          "Persona que fotografía una y otra vez amaneceres, atardeceres y la luz de la hora dorada.",
        rust.RewindBadge.consistencyChamp =>
          "Persona que no le falló a su carrete ni un solo mes. Lloviera o tronara.",
        rust.RewindBadge.unpaidPhotographer =>
          "La única razón por la que el chat del grupo tiene alguna foto.",
        rust.RewindBadge.mainCharacter =>
          "Persona a la que le encanta salir en las fotos. Cualquier escena ganaba con su presencia.",
        rust.RewindBadge.earlyBird =>
          "Persona que se levanta antes que el despertador y sale antes de que se llene todo.",
        rust.RewindBadge.nightOwl =>
          "Persona cuya cámara tiene una vida nocturna envidiable.",
        rust.RewindBadge.weekendStar =>
          "De lunes a viernes, ensayos. El fin de semana, se levanta el telón.",
        rust.RewindBadge.pawparazzi =>
          "Persona cuya mascota ha tenido más sesiones de fotos que la mayoría de las celebridades.",
        rust.RewindBadge.foodie =>
          "Persona cuyo teléfono siempre come primero.",
        rust.RewindBadge.plantParent =>
          "Persona que se detiene ante cada flor y saluda a cada hoja.",
        rust.RewindBadge.buildingBuff =>
          "Persona que ve arte en arcos, escaleras y rascacielos.",
        rust.RewindBadge.screenshotCollector =>
          "Quien guarda recibos, recetas y cada chat que merece ser recordado.",
        rust.RewindBadge.hobbyHopper =>
          "Persona que prueba de todo y domina el arte de divertirse. Una pasión nueva cada pocos meses.",
        rust.RewindBadge.indoorKid =>
          "Persona que ha hecho de estar a gusto todo un arte. Los mejores momentos se viven en casa, con la mejor compañía.",
        rust.RewindBadge.outOfOffice =>
          "Alma viajera cuya maleta apenas se vació este año.",
        rust.RewindBadge.fullThrottle =>
          "Persona que no sabe lo que es parar. Si hay un partido, un sendero o una línea de meta, ahí está.",
        rust.RewindBadge.eventHopper =>
          "La persona con la mejor agenda del grupo. Si pasaba algo, ahí estaba.",
        rust.RewindBadge.alwaysRolling =>
          "Persona que graba más vídeos que fotos. Cada fotograma no tiene precio.",
        rust.RewindBadge.fitCheck =>
          "Persona que nunca desaprovecha un buen conjunto. Cada look queda documentado.",
        rust.RewindBadge.artLover =>
          "Persona que encuentra arte en todas partes, de las galerías a cualquier esquina.",
        rust.RewindBadge.limitedEdition =>
          "Persona que no lo fotografía todo, solo la flor y nata.",
        rust.RewindBadge.happySnapper =>
          "Persona que lo fotografía todo, porque todo vale la pena.",
        rust.RewindBadge.openingCredits =>
          "Persona cuya historia acaba de empezar. Si esta es la escena inicial, lo que viene será épico.",
        rust.RewindBadge.guestStar =>
          "Persona que reserva la cámara para los momentos que de verdad cuentan, y entonces lo da todo.",
        rust.RewindBadge.mixedBag =>
          "Imposible de encasillar, y eso es lo mejor.",
      },
    );
  }

  @override
  String badgePronunciation(String pronunciation) => "$pronunciation · sust.";

  @override
  String get badgeHeading => "LO QUE MIS FOTOS\nDICEN DE MÍ";

  @override
  String get badgeHeadingLabel => "Lo que mis fotos dicen de mí";

  @override
  String badgeLabel(String title) => "Insignia $title";

  @override
  String get badgeHint => "Toca dos veces para volver a girarla";

  @override
  String get scrapbookPhotos => "Fotos capturadas";

  @override
  String get scrapbookColour => "Color del año";

  @override
  String get scrapbookPeople => "Top personas";

  @override
  String get scrapbookPlaces => "Top lugares";

  @override
  String get scrapbookTop => "TOP";

  @override
  String get finaleTop => "¡QUÉ";

  @override
  String get finaleBottom => "AÑO!";

  @override
  String get finaleLabel => "¡Qué año!";

  @override
  String get saveVideo => "Guardar vídeo";

  @override
  String get savedVideo => "Guardado";

  @override
  String get shareRewind => "Comparte tu Rewind";

  @override
  String get endCardTagline => "Revive tu año\nen fotos con";

  @override
  String get videoTitle => "CREANDO TU VÍDEO";

  @override
  List<String> get videoQuips => const [
    "Rebobinando la cinta",
    "Buscando tu mejor perfil",
    "Enseñando a Ducky a editar",
    "Añadiendo la banda sonora",
    "Puliendo cada fotograma",
    "Pasando los créditos",
  ];

  @override
  String get videoPreparing => "Preparando tus fotos";

  @override
  String get videoWrapped => "¡Y… corten!";

  @override
  String get videoDone => "Todo listo";

  @override
  String get videoAlmostDone => "Ya casi terminamos";

  @override
  String get videoKeepOpen => "Mantén Ente abierto, no tardará mucho";

  @override
  String get cancel => "Cancelar";

  @override
  String get alreadySaved => "Ya está guardado";

  @override
  String get backingUp => "Creando copia de seguridad en Ente";

  @override
  String get savedAndBackingUp =>
      "Guardado en tu galería, creando copia de seguridad en Ente";
}

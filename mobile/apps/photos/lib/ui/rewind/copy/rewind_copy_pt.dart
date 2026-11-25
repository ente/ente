import "package:intl/intl.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/copy/rewind_city_names.dart";
import "package:photos/ui/rewind/copy/rewind_copy.dart";
import "package:photos/ui/rewind/copy/rewind_copy_en.dart";

final _brazilDecimal = NumberFormat.decimalPattern("pt_BR");
final _portugalDecimal = NumberFormat.decimalPattern("pt_PT");

const _months = [
  "janeiro",
  "fevereiro",
  "março",
  "abril",
  "maio",
  "junho",
  "julho",
  "agosto",
  "setembro",
  "outubro",
  "novembro",
  "dezembro",
];

const _shortMonths = [
  "JAN",
  "FEV",
  "MAR",
  "ABR",
  "MAI",
  "JUN",
  "JUL",
  "AGO",
  "SET",
  "OUT",
  "NOV",
  "DEZ",
];

const _weekdays = [
  "segunda",
  "terça",
  "quarta",
  "quinta",
  "sexta",
  "sábado",
  "domingo",
];

String _capitalised(String word) =>
    "${word[0].toUpperCase()}${word.substring(1)}";

bool _isFeminine(int weekday) => weekday <= DateTime.friday;

String _aWeekday(int weekday) =>
    "${_isFeminine(weekday) ? "uma" : "um"} ${_weekdays[weekday - 1]}";

String _onWeekdays(int weekday) =>
    "${_isFeminine(weekday) ? "às" : "aos"} ${_weekdays[weekday - 1]}s";

class PortugueseRewindCopy extends RewindCopy {
  const PortugueseRewindCopy({this.portugal = false});

  final bool portugal;

  String _counted(int value, String one, String many) =>
      "${number(value)} ${value == 1 ? one : many}";

  @override
  String number(int value) => (portugal ? _portugalDecimal : _brazilDecimal)
      .format(value)
      .replaceAll("\u202F", "\u00A0");

  @override
  String photoTally(String number, int count) => "$number ${photoUnit(count)}";

  @override
  String photoUnit(int count) => count == 1 ? "foto" : "fotos";

  @override
  Map<String, String> get cityNames => portugueseCityNames;

  @override
  String shortDate(int day, int month, int year) =>
      "$day ${_shortMonths[month - 1]} $year";

  @override
  String monthBanner(int month) => _months[month - 1].toUpperCase();

  @override
  String monthName(int month) => _capitalised(_months[month - 1]);

  @override
  String get close => "Fechar";

  @override
  String get playMusic => "Tocar música";

  @override
  String get muteMusic => "Silenciar música";

  @override
  String get share => "Compartilhar";

  @override
  String get shareVideo => "Compartilhar vídeo";

  @override
  String get nextCard => "Próximo cartão";

  @override
  String pageOf(int page, int count) => "Página $page de $count";

  @override
  String get dismiss => "Descartar";

  @override
  String get watch => "Ver";

  @override
  String get watchAgain => "Ver de novo";

  @override
  String get resume => "Continuar";

  @override
  String get newStatus => "Novo";

  @override
  String get newSticker => "NOVO";

  @override
  String progress(int page, int count) => "$page de $count";

  @override
  String get readyTitle => "Seu Rewind ${RewindEdition.year} está pronto";

  @override
  String get readyBody => "Seu ano em fotos. É só abrir quando quiser.";

  @override
  String get newCardsTitle =>
      "Seu Rewind ${RewindEdition.year} ganhou novos cartões";

  @override
  String get newCardsBody => "Abra de novo para ver as novidades.";

  @override
  RewindLines get coverTagline =>
      (you: "SEU ANO EM FOTOS", me: "MEU ANO EM FOTOS");

  @override
  String get tapToStart => "Toque para começar";

  @override
  RewindSetupLines setup(RewindSetup setup) => switch (setup) {
    RewindSetup.palette => (
      headlines: ["SEU ANO\nTEVE UMA COR"],
      callout: "COMBINA\nCOM VOCÊ!",
    ),
    RewindSetup.places => (
      headlines: ["VOCÊ FOI\nLONGE."],
      callout: "E A CÂMERA\nTAMBÉM FOI.",
    ),
    RewindSetup.people => (
      headlines: ["ALGUNS ROSTOS\nNÃO PARAVAM DE\nAPARECER."],
      callout: "TIPO, MUITO!",
    ),
    RewindSetup.busiestDay => (
      headlines: ["UM DIA,\nVOCÊ CLICOU,\nCLICOU…"],
      callout: "E CLICOU!",
    ),
    RewindSetup.newFaces => (
      headlines: ["O ELENCO\nCRESCEU"],
      callout: "BOAS-VINDAS À FAMÍLIA!",
    ),
    RewindSetup.favourites => (
      headlines: ["O MELHOR\nDO MELHOR."],
      callout: "MERECEM UMA ESTRELA!",
    ),
    RewindSetup.ritual => (
      headlines: ["CERTAS COISAS\nTINHAM HORA", "MARCADA."],
      callout: "QUASE NA HORA!",
    ),
    RewindSetup.ritualStreak => (
      headlines: ["VOCÊ CRIOU\nRITUAIS."],
      callout: "UMA FOTO POR DIA.",
    ),
    RewindSetup.likes => (
      headlines: ["SEU FEED\nBOMBOU!"],
      callout: "E ESSA AQUI, ENTÃO!",
    ),
    RewindSetup.mosaic => (
      headlines: ["TUDO SE\nENCAIXA."],
      callout: "FOTO A FOTO.",
    ),
    RewindSetup.badge => (
      headlines: ["DEPOIS DE UM\nANO DESSES…"],
      callout: "VOCÊ MERECE UMA MEDALHA!",
    ),
  };

  @override
  String tunnelAgo(int days) =>
      days < 1 ? "HOJE MAIS CEDO" : "HÁ ${_counted(days, "DIA", "DIAS")}";

  @override
  String get tunnelStartTitle => "COMEÇOU AQUI";

  @override
  RewindLines get tunnelStartBody =>
      (you: "Sua primeira foto do ano.", me: "Minha primeira foto do ano.");

  @override
  String get tunnelGoOnHint => "TOQUE OU DESLIZE PARA CIMA PARA SEGUIR";

  @override
  String get tunnelFlyBackHint => "DESLIZE PARA BAIXO PARA VOAR DE VOLTA";

  @override
  String tunnelMomentEyebrow(DateTime day) =>
      "${_aWeekday(day.weekday).toUpperCase()} "
      "DE ${monthBanner(day.month)}";

  @override
  String get tunnelMomentTitle => "LEMBRA DISSO?";

  @override
  RewindLines get tunnelMomentBody =>
      (you: "Um momento do seu ano.", me: "Um momento do meu ano.");

  @override
  String get tunnelLoading => "CARREGANDO A FITA";

  @override
  String get tunnelFlyAgain => "VOAR DE NOVO";

  @override
  RewindLines get photosCountKicker => (
    you: "EM ${RewindEdition.year}, VOCÊ CLICOU",
    me: "EM ${RewindEdition.year}, EU CLIQUEI",
  );

  @override
  String memoriesUnit(int count) => count == 1 ? "memória" : "memórias";

  @override
  RewindLines get topPercentKicker =>
      (you: "NO ENTE, VOCÊ ESTÁ NO", me: "NO ENTE, ESTOU NO");

  @override
  String topPercent(int percent) => "TOP $percent%";

  @override
  String memoriesSaved(int count) =>
      "${_counted(count, "memória guardada", "memórias guardadas")}, "
      "e a contagem continua!";

  @override
  String get placesQuestion => "ONDE VOCÊ MAIS FOTOGRAFOU?";

  @override
  String get placesHint => "Toque num selo e arrisque um palpite.";

  @override
  String placesPicked(String city) => "$city? Vamos conferir\nos carimbos.";

  @override
  RewindLines placesHeading({required bool travelled}) => travelled
      ? (you: "SUAS FOTOS VIAJARAM", me: "MINHAS FOTOS VIAJARAM")
      : (you: "SEU LUGAR CAMPEÃO", me: "MEU LUGAR CAMPEÃO");

  @override
  String distance(int km) => "${number(km)} KM";

  @override
  String placesWon(String city, int photos) =>
      "$city ganhou com ${this.photos(photos)}.";

  @override
  String placesNext(List<String> cities) => switch (cities) {
    [final next] => "Logo atrás veio $next.",
    [final first, final second, ...] => "Logo atrás vieram $first e $second.",
    _ => "",
  };

  @override
  String placesPlaced(String city, int place) =>
      "$city ficou em ${place == 2 ? "segundo" : "terceiro"}.";

  @override
  String placesHad(String city, int photos) => "$city teve ${number(photos)}.";

  @override
  RewindLines get globeKicker =>
      (you: "SUAS FOTOS VOARAM", me: "MINHAS FOTOS VOARAM");

  @override
  String globeLaps(double laps) =>
      "Isso dá ${laps.toStringAsFixed(1).replaceFirst(".", ",")} voltas "
      "ao mundo.";

  @override
  String globeLapShare(int percent) =>
      "Isso dá $percent% de uma volta ao mundo.";

  @override
  String get globeHint => "ARRASTE PARA GIRAR";

  @override
  String globeLabel(int km, String laps) =>
      "Suas fotos voaram ${number(km)} quilômetros. $laps";

  @override
  String globeTally(int cities, int countries) =>
      "${_counted(cities, "CIDADE", "CIDADES")}"
      "  ·  "
      "${_counted(countries, "PAÍS", "PAÍSES")}";

  @override
  String get raceQuestion => "QUEM MAIS APARECEU?";

  @override
  String get raceHint => "Toque num rosto e arrisque um palpite.";

  @override
  String racePicked(String name) => "$name? aposta ousada";

  @override
  String raceOvertakes(String passer, String passed) =>
      "$passer ULTRAPASSA $passed!";

  @override
  String raceWinner(String name) => "$name APARECEU MAIS!";

  @override
  RewindLines get raceCalledIt =>
      (you: "ACERTOU EM CHEIO!", me: "ACERTEI EM CHEIO!");

  @override
  String get raceClose => "FOI QUASE!";

  @override
  String get raceMissed => "NÃO FOI DESTA VEZ!";

  @override
  RewindLines get racePick => (you: "SEU PALPITE", me: "MEU PALPITE");

  @override
  RewindLines boothBilling(int place) => switch (place) {
    0 => (you: "SEU NÚMERO 1", me: "MEU NÚMERO 1"),
    1 => (you: "SEMPRE AO SEU LADO", me: "SEMPRE AO MEU LADO"),
    _ => (
      you: "${RewindEdition.year} FOI MELHOR COM",
      me: "${RewindEdition.year} FOI MELHOR COM",
    ),
  };

  @override
  String boothPhotos(int count) => "${photos(count)} este ano!";

  @override
  RewindLines busiestDayKicker(int day, int month) {
    final onDay = "Em ${day == 1 ? "1º" : "$day"} de ${_months[month - 1]}";
    return (you: "$onDay, você tirou", me: "$onDay, eu tirei");
  }

  @override
  String get busiestDayLine => "Um dia para ficar na história!";

  @override
  String newFacesTitle(int count) =>
      count == 1 ? "1 ROSTO NOVO" : "${number(count)} ROSTOS NOVOS";

  @override
  RewindLines newFacesLine(int count) {
    final debuted = count == 1 ? "estreou" : "estrearam";
    return (
      you: "$debuted na sua galeria este ano.",
      me: "$debuted na minha galeria este ano.",
    );
  }

  @override
  String colourName(rust.RewindColour colour) => switch (colour) {
    rust.RewindColour.cherryBomb => "CEREJA EXPLOSIVA",
    rust.RewindColour.tangerinePop => "LARANJADA",
    rust.RewindColour.lemonDrop => "LIMÃO AZEDINHO",
    rust.RewindColour.pistachio => "PISTACHE",
    rust.RewindColour.berryBlue => "AZUL MIRTILO",
    rust.RewindColour.lavenderFizz => "SODA DE LAVANDA",
    rust.RewindColour.bubblegum => "CHICLETE",
    rust.RewindColour.hotCocoa => "BRIGADEIRO",
    rust.RewindColour.marshmallow => "SUSPIRO",
    rust.RewindColour.midnightCola => "COLA DA MEIA-NOITE",
  };

  String _colourWord(rust.RewindColour colour) => switch (colour) {
    rust.RewindColour.cherryBomb => "vermelho",
    rust.RewindColour.tangerinePop => "laranja",
    rust.RewindColour.lemonDrop => "amarelo",
    rust.RewindColour.pistachio => "verde",
    rust.RewindColour.berryBlue => "azul",
    rust.RewindColour.lavenderFizz => "roxo",
    rust.RewindColour.bubblegum => "rosa",
    rust.RewindColour.hotCocoa => "marrom",
    rust.RewindColour.marshmallow => "branco",
    rust.RewindColour.midnightCola => "preto",
  };

  @override
  RewindLines colourLine(int percent, rust.RewindColour colour) => (
    you: "O ${_colourWord(colour)} dominou $percent% das suas fotos.",
    me: "O ${_colourWord(colour)} dominou $percent% das minhas fotos.",
  );

  @override
  String get favouritesTitle => "SEUS FAVORITOS";

  @override
  String get myFavouritesTitle => "MEUS FAVORITOS";

  @override
  String get myFavouriteTitle => "MEU FAVORITO";

  @override
  String get favouritesLine => "Memórias para guardar com carinho.";

  @override
  String get favouriteLine => "Uma memória para guardar com carinho.";

  @override
  String get favouritesLabel => "Seus favoritos. $favouritesLine";

  @override
  RewindLines get habitKicker =>
      (you: "SEU RITUAL SEMANAL", me: "MEU RITUAL SEMANAL");

  @override
  String clockHour(int hour) => "${hour.toString().padLeft(2, "0")}:00";

  @override
  String habitTitle(int weekday, int hour) =>
      "${_capitalised(_weekdays[weekday - 1])}s, ${hour}h";

  @override
  RewindLines habitLine(int percent, int weekday) => (
    you: "$percent% das suas fotos foram tiradas ${_onWeekdays(weekday)}.",
    me: "$percent% das minhas fotos foram tiradas ${_onWeekdays(weekday)}.",
  );

  @override
  String habitLabel(String title, String line) =>
      "Seu ritual semanal: $title. $line";

  @override
  String weekdayInitial(int weekday) => _weekdays[weekday - 1][0].toUpperCase();

  @override
  String get crowdFavouriteTitle => "SUCESSO DE PÚBLICO";

  @override
  RewindLines get crowdFavouriteLine =>
      (you: "Sua foto mais curtida.", me: "Minha foto mais curtida.");

  @override
  String get crowdFavouriteLabel =>
      "Sucesso de público. ${crowdFavouriteLine.you}";

  @override
  RewindLines get streakKicker =>
      (you: "SUA MAIOR SEQUÊNCIA", me: "MINHA MAIOR SEQUÊNCIA");

  @override
  String checkInsLabel(int count) =>
      count == 1 ? "Check-in\neste ano" : "Check-ins\neste ano";

  @override
  String ritualsContinuedLabel(int count) =>
      count == 1 ? "Ritual\nmantido" : "Rituais\nmantidos";

  @override
  String get mostActiveMonthLabel => "Mês mais\nativo";

  @override
  String streakLabel({
    required int streak,
    required int checkIns,
    required int month,
    required int continued,
  }) =>
      "Sua maior sequência de rituais: ${number(streak)}. "
      "${_counted(checkIns, "check-in", "check-ins")} "
      "este ano, a maioria em ${_months[month - 1]}. "
      "${_counted(continued, "ritual segue firme", "rituais seguem firmes")}.";

  @override
  RewindLines get mosaicSelf => (you: "VOCÊ", me: "EU");

  @override
  String get familiarFace => "UM ROSTO CONHECIDO";

  @override
  String mosaicMoments(int count) =>
      "EM ${_counted(count, "MOMENTO", "MOMENTOS")}.";

  @override
  String get mosaicHint => "Toque ou amplie para explorar";

  @override
  RewindBadgeCopy badge(rust.RewindBadge badge) {
    final english = const EnglishRewindCopy().badge(badge);
    return (
      title: english.title,
      pronunciation: english.pronunciation,
      definition: switch (badge) {
        rust.RewindBadge.sunChaser =>
          "Pessoa que não perde um nascer do sol, um pôr do sol nem a luz da hora dourada.",
        rust.RewindBadge.consistencyChamp =>
          "Pessoa que marcou presença na galeria todo santo mês. Faça chuva ou faça sol.",
        rust.RewindBadge.unpaidPhotographer =>
          "A única razão de haver fotos no grupo dos amigos.",
        rust.RewindBadge.mainCharacter =>
          "Pessoa que adora sair nas fotos. Cada cena ficou melhor com essa presença.",
        rust.RewindBadge.earlyBird =>
          "Pessoa que acorda antes do despertador e sai antes da multidão.",
        rust.RewindBadge.nightOwl =>
          "Pessoa cuja galeria tem uma vida noturna agitada.",
        rust.RewindBadge.weekendStar =>
          "De segunda a sexta é só ensaio. O fim de semana é a estreia.",
        rust.RewindBadge.pawparazzi =>
          "Pessoa cujo animal de estimação já teve mais sessões de fotos do que muita celebridade.",
        rust.RewindBadge.foodie => "Pessoa cujo celular sempre come primeiro.",
        rust.RewindBadge.plantParent =>
          "Pessoa que para em cada flor e cumprimenta cada folhinha.",
        rust.RewindBadge.buildingBuff =>
          "Pessoa que vê arte em arcos, escadarias e horizontes urbanos.",
        rust.RewindBadge.screenshotCollector =>
          "Quem guarda recibos, receitas e cada conversa que vale a pena lembrar.",
        rust.RewindBadge.hobbyHopper =>
          "Pau para toda obra, especialista em diversão. Uma nova paixão a cada estação.",
        rust.RewindBadge.indoorKid =>
          "Pessoa que domina a arte do aconchego. Os melhores momentos acontecem em casa, com as melhores pessoas.",
        rust.RewindBadge.outOfOffice =>
          "Quem explorou tanto que mal desfez a mala este ano.",
        rust.RewindBadge.fullThrottle =>
          "Pessoa que não sabe o que é “sossegar”. Jogo, trilha ou linha de chegada? Presença garantida.",
        rust.RewindBadge.eventHopper =>
          "Quem tem a melhor agenda da turma. Se aconteceu, estava lá.",
        rust.RewindBadge.alwaysRolling =>
          "Pessoa que grava mais vídeos do que tira fotos. Cada quadro vale ouro.",
        rust.RewindBadge.fitCheck =>
          "Pessoa que nunca desperdiça uma boa roupa. Cada look vira foto.",
        rust.RewindBadge.artLover =>
          "Pessoa que encontra arte por toda parte, das galerias às esquinas.",
        rust.RewindBadge.limitedEdition =>
          "Pessoa que não fotografa tudo, só o que vale a pena.",
        rust.RewindBadge.happySnapper =>
          "Pessoa que fotografa tudo, porque tudo merece um clique.",
        rust.RewindBadge.openingCredits =>
          "Pessoa cuja história mal começou. Se esta é a cena de abertura, o resto vai ser épico.",
        rust.RewindBadge.guestStar =>
          "Pessoa que guarda os cliques para os momentos que importam, e aí vai com tudo.",
        rust.RewindBadge.mixedBag =>
          "Impossível de rotular, e essa é a melhor parte.",
      },
    );
  }

  @override
  String badgePronunciation(String pronunciation) => "$pronunciation · subst.";

  @override
  String get badgeHeading => "O QUE MINHAS FOTOS\nDIZEM SOBRE MIM";

  @override
  String get badgeHeadingLabel => "O que minhas fotos dizem sobre mim";

  @override
  String badgeLabel(String title) => "Medalha $title";

  @override
  String get badgeHint => "Toque duas vezes para virar de novo";

  @override
  String get scrapbookPhotos => "Fotos tiradas";

  @override
  String get scrapbookColour => "Cor do ano";

  @override
  String get scrapbookPeople => "Top pessoas";

  @override
  String get scrapbookPlaces => "Top lugares";

  @override
  String get scrapbookTop => "TOP";

  @override
  String get finaleTop => "QUE";

  @override
  String get finaleBottom => "ANO!";

  @override
  String get finaleLabel => "Que ano!";

  @override
  String get saveVideo => "Salvar vídeo";

  @override
  String get savedVideo => "Salvo";

  @override
  String get shareRewind => "Mostre seu Rewind";

  @override
  String get endCardTagline => "Relembre\nseu ano com";

  @override
  String get videoTitle => "SEU VÍDEO NO FORNO";

  @override
  List<String> get videoQuips => const [
    "Rebobinando a fita",
    "Escolhendo seus melhores ângulos",
    "Ensinando o Ducky a editar",
    "Colocando a trilha sonora",
    "Caprichando em cada quadro",
    "Subindo os créditos",
  ];

  @override
  String get videoPreparing => "Preparando suas fotos";

  @override
  String get videoWrapped => "E… corta!";

  @override
  String get videoDone => "Tudo pronto";

  @override
  String get videoAlmostDone => "Quase lá";

  @override
  String get videoKeepOpen => "Deixe o Ente aberto, não vai demorar";

  @override
  String get cancel => "Cancelar";

  @override
  String get alreadySaved => "Já está salvo";

  @override
  String get backingUp => "Fazendo backup no Ente";

  @override
  String get savedAndBackingUp =>
      "Salvo na sua galeria, fazendo backup no Ente";
}

import 'dart:ui';

class ChangeLogStrings {
  final List<ChangeLogEntryStrings> entries;

  const ChangeLogStrings({required this.entries});

  static ChangeLogStrings? maybeForLocale(
    Locale locale, {
    bool isLocalGallery = false,
    required bool isAndroid,
  }) {
    final key = locale.countryCode != null && locale.countryCode!.isNotEmpty
        ? '${locale.languageCode}_${locale.countryCode}'
        : locale.languageCode;
    final strings =
        _translations[key] ??
        _translations[locale.languageCode] ??
        _translations['en'];

    if (strings == null) {
      return null;
    }

    return strings.forAudience(
      isLocalGallery: isLocalGallery,
      isAndroid: isAndroid,
    );
  }

  ChangeLogStrings? forAudience({
    bool isLocalGallery = false,
    required bool isAndroid,
  }) {
    final visibleEntries = entries
        .where((entry) => !entry.isAndroidOnly || isAndroid)
        .where((entry) => !entry.isIOSOnly || !isAndroid)
        .where(
          (entry) =>
              isLocalGallery ? !entry.isOnlineOnly : !entry.isLocalGalleryOnly,
        )
        .toList(growable: false);
    return visibleEntries.isEmpty
        ? null
        : ChangeLogStrings(entries: visibleEntries);
  }

  static bool hasContentForLocale(
    Locale locale, {
    bool isLocalGallery = false,
    required bool isAndroid,
  }) {
    return maybeForLocale(
          locale,
          isLocalGallery: isLocalGallery,
          isAndroid: isAndroid,
        ) !=
        null;
  }

  static const Map<String, ChangeLogStrings> _translations = {
    'en': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Review old photos, reclaim space',
          description:
              'Swipe through your gallery and mark photos you no longer want for deletion.\n\nFind it in Settings → Free up space → Old photos.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Revamped photo picker',
          description:
              'When attaching photos or videos in another app using Ente as the photo picker, you can now explore your gallery, search your library, and browse albums.',
          isAndroidOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Sort albums by filename',
          description: 'Sort photos and videos in your albums by filename.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Now in Indonesian and Swedish',
          description: 'You can now use Ente Photos in Indonesian or Swedish.',
        ),
        ChangeLogEntryStrings(
          title: 'More reliable backups',
          description:
              'We fixed a few edge cases where backups could stall or fail.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'And more!',
          description:
              'Quicker photo editor opening, more reliable crops in Original mode, and fewer repeat trip memories.',
        ),
      ],
    ),
    'ca': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Revisa fotos antigues i recupera espai',
          description:
              'Fes lliscar les fotos de la galeria i marca per suprimir les que ja no vulguis.\n\nHo trobaràs a Configuració → Allibera espai → Old photos.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Selector de fotos renovat',
          description:
              'Quan adjuntis fotos o vídeos en una altra aplicació fent servir Ente com a selector de fotos, ara podràs explorar la galeria, cercar a la biblioteca i navegar pels àlbums.',
          isAndroidOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Ordena els àlbums per nom de fitxer',
          description:
              'Ordena les fotos i els vídeos dels àlbums per nom de fitxer.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Ara en indonesi i suec',
          description: 'Ara pots fer servir Ente Photos en indonesi o en suec.',
        ),
        ChangeLogEntryStrings(
          title: 'Còpies de seguretat més fiables',
          description:
              'Hem corregit alguns casos poc habituals en què les còpies de seguretat es podien encallar o fallar.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'I més coses!',
          description:
              'L’editor de fotos s’obre més de pressa, el retall en mode Original és més fiable i els records de viatges es repeteixen menys.',
        ),
      ],
    ),
    'cs': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Projděte si staré fotky a uvolněte místo',
          description:
              'Procházejte fotky v galerii posouváním a označte ke smazání ty, které už nechcete.\n\nTuto funkci najdete v nabídce Nastavení → Uvolnit místo → Old photos.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Přepracovaný výběr fotek',
          description:
              'Když v jiné aplikaci přikládáte fotky nebo videa pomocí výběru v Ente, můžete teď procházet galerii, vyhledávat v knihovně a prohlížet alba.',
          isAndroidOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Řazení alb podle názvu souboru',
          description: 'Seřaďte fotky a videa v albech podle názvu souboru.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Nově v indonéštině a švédštině',
          description:
              'Ente Photos můžete teď používat v indonéštině nebo švédštině.',
        ),
        ChangeLogEntryStrings(
          title: 'Spolehlivější zálohování',
          description:
              'Opravili jsme několik ojedinělých případů, kdy se zálohování mohlo zaseknout nebo selhat.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'A další novinky!',
          description:
              'Editor fotek se otevírá rychleji, ořez v režimu Original je spolehlivější a vzpomínky na výlety se méně často opakují.',
        ),
      ],
    ),
    'de': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Alte Fotos durchsehen und Platz schaffen',
          description:
              'Wische durch deine Galerie und markiere Fotos, die du nicht mehr behalten möchtest, zum Löschen.\n\nDu findest die Funktion unter Einstellungen → Speicherplatz freigeben → Old photos.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Überarbeitete Fotoauswahl',
          description:
              'Wenn du Fotos oder Videos in einer anderen App anhängst und Ente zur Fotoauswahl verwendest, kannst du jetzt deine Galerie erkunden, deine Mediathek durchsuchen und in Alben stöbern.',
          isAndroidOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Alben nach Dateiname sortieren',
          description:
              'Sortiere Fotos und Videos in deinen Alben nach Dateiname.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Jetzt auf Indonesisch und Schwedisch',
          description:
              'Du kannst Ente Photos jetzt auf Indonesisch oder Schwedisch nutzen.',
        ),
        ChangeLogEntryStrings(
          title: 'Zuverlässigere Datensicherung',
          description:
              'Wir haben einige seltene Fälle behoben, in denen die Datensicherung hängen bleiben oder fehlschlagen konnte.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Und mehr!',
          description:
              'Der Fotoeditor öffnet sich schneller, das Zuschneiden im Modus Original funktioniert zuverlässiger, und Reiseerinnerungen wiederholen sich seltener.',
        ),
      ],
    ),
    'es': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Revisa fotos antiguas y recupera espacio',
          description:
              'Desliza para recorrer tu galería y marca para eliminar las fotos que ya no quieras conservar.\n\nEncuentra esta función en Configuración → Liberar espacio → Old photos.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Selector de fotos renovado',
          description:
              'Cuando adjuntes fotos o vídeos en otra aplicación usando Ente como selector de fotos, ahora puedes explorar tu galería, buscar en tu biblioteca y recorrer tus álbumes.',
          isAndroidOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Ordena los álbumes por nombre de archivo',
          description:
              'Ordena las fotos y los vídeos de tus álbumes por nombre de archivo.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Ahora en indonesio y sueco',
          description: 'Ya puedes usar Ente Photos en indonesio o sueco.',
        ),
        ChangeLogEntryStrings(
          title: 'Copias de seguridad más fiables',
          description:
              'Hemos corregido algunos casos poco habituales en los que las copias de seguridad podían atascarse o fallar.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '¡Y más!',
          description:
              'El editor de fotos se abre más rápido, el recorte en modo Original es más fiable y hay menos recuerdos de viajes repetidos.',
        ),
      ],
    ),
    'fr': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Triez vos anciennes photos et libérez de l’espace',
          description:
              'Faites défiler votre galerie d’un geste et marquez les photos que vous ne souhaitez plus garder pour les supprimer.\n\nRetrouvez cette fonction dans Paramètres → Libérer de l\'espace → Old photos.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Sélecteur de photos repensé',
          description:
              'Lorsque vous joignez des photos ou des vidéos dans une autre application en utilisant Ente comme sélecteur de photos, vous pouvez désormais explorer votre galerie, faire des recherches dans votre photothèque et parcourir vos albums.',
          isAndroidOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Tri des albums par nom de fichier',
          description:
              'Triez les photos et vidéos de vos albums par nom de fichier.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Désormais en indonésien et en suédois',
          description:
              'Vous pouvez désormais utiliser Ente Photos en indonésien ou en suédois.',
        ),
        ChangeLogEntryStrings(
          title: 'Sauvegardes plus fiables',
          description:
              'Nous avons corrigé quelques cas rares où les sauvegardes pouvaient se bloquer ou échouer.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Et plus encore !',
          description:
              'L’éditeur photo s’ouvre plus vite, le recadrage en mode Original est plus fiable et les souvenirs de voyage se répètent moins.',
        ),
      ],
    ),
    'id': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Tinjau foto lama dan kosongkan ruang',
          description:
              'Geser untuk menelusuri galeri dan tandai foto yang tidak ingin Anda simpan lagi untuk dihapus.\n\nTemukan fitur ini di Pengaturan → Bersihkan ruang → Old photos.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Pemilih foto yang diperbarui',
          description:
              'Saat melampirkan foto atau video di aplikasi lain dengan Ente sebagai pemilih foto, Anda kini bisa menjelajahi galeri, mencari di pustaka, dan menelusuri album.',
          isAndroidOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Urutkan album berdasarkan nama file',
          description:
              'Urutkan foto dan video di album Anda berdasarkan nama file.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Kini dalam bahasa Indonesia dan Swedia',
          description:
              'Kini Anda bisa menggunakan Ente Photos dalam bahasa Indonesia atau Swedia.',
        ),
        ChangeLogEntryStrings(
          title: 'Pencadangan yang lebih andal',
          description:
              'Kami memperbaiki beberapa kasus yang jarang terjadi saat pencadangan bisa macet atau gagal.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Dan masih banyak lagi!',
          description:
              'Editor foto terbuka lebih cepat, pemotongan dalam mode Original lebih andal, dan kenangan perjalanan yang sama lebih jarang muncul.',
        ),
      ],
    ),
    'it': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Rivedi le vecchie foto e libera spazio',
          description:
              'Scorri la galleria e contrassegna per l’eliminazione le foto che non vuoi più tenere.\n\nTrovi questa funzione in Impostazioni → Libera spazio → Old photos.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Selettore di foto rinnovato',
          description:
              'Quando alleghi foto o video in un’altra app usando Ente come selettore di foto, ora puoi esplorare la galleria, cercare nella tua raccolta e sfogliare gli album.',
          isAndroidOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Ordina gli album per nome del file',
          description:
              'Ordina le foto e i video dei tuoi album per nome del file.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Ora in indonesiano e svedese',
          description:
              'Ora puoi usare Ente Photos in indonesiano o in svedese.',
        ),
        ChangeLogEntryStrings(
          title: 'Backup più affidabili',
          description:
              'Abbiamo risolto alcuni casi poco comuni in cui i backup potevano bloccarsi o non riuscire.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'E altro ancora!',
          description:
              'L’editor di foto si apre più rapidamente, il ritaglio in modalità Original è più affidabile e i ricordi di viaggio si ripetono meno spesso.',
        ),
      ],
    ),
    'ja': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: '昔の写真を見直して空き容量を増やす',
          description:
              'ギャラリーをスワイプしながら、不要になった写真に削除のマークを付けられます。\n\nこの機能は「設定 → スペースを解放する → Old photos」から利用できます。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '写真の選択画面を刷新',
          description:
              '他のアプリで Ente を写真の選択画面として使い、写真や動画を添付するときに、ギャラリーを見たり、ライブラリを検索したり、アルバムを閲覧したりできるようになりました。',
          isAndroidOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'アルバム内をファイル名で並べ替え',
          description: 'アルバム内の写真や動画をファイル名で並べ替えられます。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'インドネシア語とスウェーデン語に対応',
          description: 'Ente Photos をインドネシア語またはスウェーデン語で利用できるようになりました。',
        ),
        ChangeLogEntryStrings(
          title: 'より安定したバックアップ',
          description: 'まれにバックアップが途中で止まったり失敗したりする問題を修正しました。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'その他の改善',
          description:
              '写真エディターがより速く開き、Original モードでより安定して切り抜けるようになり、同じ旅行の思い出が表示される頻度も減りました。',
        ),
      ],
    ),
    'ko': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: '오래된 사진을 정리하고 공간 확보',
          description:
              '갤러리를 스와이프하면서 더 이상 보관하고 싶지 않은 사진을 삭제 대상으로 표시할 수 있어요.\n\n이 기능은 설정 → 공간 확보 → Old photos에서 찾을 수 있어요.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '새로워진 사진 선택기',
          description:
              '다른 앱에서 Ente를 사진 선택기로 사용해 사진이나 동영상을 첨부할 때, 이제 갤러리를 둘러보고 라이브러리에서 검색하고 앨범을 살펴볼 수 있어요.',
          isAndroidOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '앨범을 파일 이름으로 정렬',
          description: '앨범에 있는 사진과 동영상을 파일 이름으로 정렬할 수 있어요.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '이제 인도네시아어와 스웨덴어로',
          description: '이제 Ente Photos를 인도네시아어 또는 스웨덴어로 사용할 수 있어요.',
        ),
        ChangeLogEntryStrings(
          title: '더 안정적인 백업',
          description: '드물게 백업이 멈추거나 실패할 수 있던 문제를 수정했어요.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '그 밖의 개선 사항',
          description:
              '사진 편집기가 더 빨리 열리고, Original 모드에서 더 안정적으로 자를 수 있으며, 같은 여행 추억이 반복해서 표시되는 일이 줄었어요.',
        ),
      ],
    ),
    'nl': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Bekijk oude foto’s en maak ruimte vrij',
          description:
              'Veeg door je galerij en markeer foto’s die je niet meer wilt bewaren om ze later te verwijderen.\n\nJe vindt deze functie onder Instellingen → Ruimte vrijmaken → Old photos.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Vernieuwde fotokiezer',
          description:
              'Als je in een andere app foto’s of video’s bijvoegt met Ente als fotokiezer, kun je nu je galerij bekijken, in je bibliotheek zoeken en door albums bladeren.',
          isAndroidOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Sorteer albums op bestandsnaam',
          description:
              'Sorteer foto’s en video’s in je albums op bestandsnaam.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Nu in het Indonesisch en Zweeds',
          description:
              'Je kunt Ente Photos nu in het Indonesisch of Zweeds gebruiken.',
        ),
        ChangeLogEntryStrings(
          title: 'Betrouwbaardere back-ups',
          description:
              'We hebben enkele uitzonderlijke gevallen verholpen waarin back-ups konden vastlopen of mislukken.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'En meer!',
          description:
              'De foto-editor opent sneller, bijsnijden in de modus Original werkt betrouwbaarder en reisherinneringen worden minder vaak herhaald.',
        ),
      ],
    ),
    'no': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Se gjennom gamle bilder og frigjør lagringsplass',
          description:
              'Sveip gjennom galleriet og merk uønskede bilder for sletting.\n\nDu finner funksjonen under Settings → Frigjør lagringsplass → Old photos.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Fornyet bildevelger',
          description:
              'Når du legger ved bilder eller videoer i en annen app med Ente som bildevelger, kan du nå utforske galleriet, søke i biblioteket og bla gjennom albumene dine.',
          isAndroidOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Sorter album etter filnavn',
          description:
              'Sorter bilder og videoer i albumene dine etter filnavn.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Nå på indonesisk og svensk',
          description:
              'Du kan nå bruke Ente Photos på indonesisk eller svensk.',
        ),
        ChangeLogEntryStrings(
          title: 'Mer pålitelig sikkerhetskopiering',
          description:
              'Vi har rettet noen sjeldne tilfeller der sikkerhetskopieringen kunne stoppe opp eller mislykkes.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Og mer!',
          description:
              'Bilderedigeringen åpnes raskere, beskjæring i Original-modus fungerer mer pålitelig, og reiseminner gjentas sjeldnere.',
        ),
      ],
    ),
    'pl': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Przejrzyj stare zdjęcia i zwolnij miejsce',
          description:
              'Przeglądaj galerię, przesuwając palcem, i oznacz do usunięcia zdjęcia, których nie chcesz już przechowywać.\n\nTę funkcję znajdziesz w menu Ustawienia → Zwolnij miejsce → Old photos.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Odnowiony wybór zdjęć',
          description:
              'Gdy dołączasz zdjęcia lub filmy w innej aplikacji, używając Ente do ich wyboru, możesz teraz przeglądać galerię, wyszukiwać w bibliotece i przeglądać zawartość albumów.',
          isAndroidOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Sortuj albumy według nazwy pliku',
          description: 'Sortuj zdjęcia i filmy w albumach według nazwy pliku.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Teraz po indonezyjsku i szwedzku',
          description:
              'Możesz teraz korzystać z Ente Photos po indonezyjsku lub szwedzku.',
        ),
        ChangeLogEntryStrings(
          title: 'Bardziej niezawodne kopie zapasowe',
          description:
              'Naprawiliśmy kilka rzadkich przypadków, w których tworzenie kopii zapasowej mogło się zatrzymać lub nie powieść.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'I więcej!',
          description:
              'Edytor zdjęć otwiera się szybciej, kadrowanie w trybie Original działa pewniej, a wspomnienia z podróży rzadziej się powtarzają.',
        ),
      ],
    ),
    'pt_BR': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Revise fotos antigas e libere espaço',
          description:
              'Deslize pela galeria e marque para exclusão as fotos que você não quer mais guardar.\n\nEncontre esse recurso em Opções → Liberar espaço → Old photos.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Seletor de fotos renovado',
          description:
              'Ao anexar fotos ou vídeos em outro app usando o Ente como seletor de fotos, você agora pode explorar a galeria, buscar na biblioteca e navegar pelos álbuns.',
          isAndroidOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Ordene álbuns por nome do arquivo',
          description:
              'Ordene fotos e vídeos dos seus álbuns por nome do arquivo.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Agora em indonésio e sueco',
          description:
              'Agora você pode usar o Ente Photos em indonésio ou sueco.',
        ),
        ChangeLogEntryStrings(
          title: 'Backups mais confiáveis',
          description:
              'Corrigimos alguns casos raros em que os backups podiam travar ou falhar.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'E mais!',
          description:
              'O editor de fotos abre mais rápido, o recorte no modo Original é mais confiável e as memórias de viagens se repetem menos.',
        ),
      ],
    ),
    'pt_PT': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Reveja fotos antigas e liberte espaço',
          description:
              'Deslize pela galeria e marque para apagar as fotos que já não quer guardar.\n\nEncontre esta funcionalidade em Settings → Libertar espaço → Old photos.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Seletor de fotos renovado',
          description:
              'Ao anexar fotos ou vídeos noutra aplicação com o Ente como seletor de fotos, pode agora explorar a galeria, pesquisar na biblioteca e navegar pelos álbuns.',
          isAndroidOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Ordene álbuns por nome de ficheiro',
          description:
              'Ordene as fotos e os vídeos dos seus álbuns por nome de ficheiro.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Agora em indonésio e sueco',
          description: 'Já pode usar o Ente Photos em indonésio ou sueco.',
        ),
        ChangeLogEntryStrings(
          title: 'Cópias de segurança mais fiáveis',
          description:
              'Corrigimos alguns casos raros em que as cópias de segurança podiam ficar bloqueadas ou falhar.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'E muito mais!',
          description:
              'O editor de fotos abre mais depressa, o recorte no modo Original é mais fiável e as memórias de viagens repetem-se menos.',
        ),
      ],
    ),
    'ro': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Revizuiește fotografiile vechi și eliberează spațiu',
          description:
              'Glisează prin galerie și marchează pentru ștergere fotografiile pe care nu mai vrei să le păstrezi.\n\nGăsești funcția în Setări → Eliberați spațiu → Old photos.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Selector de fotografii refăcut',
          description:
              'Când atașezi fotografii sau videoclipuri în altă aplicație folosind Ente ca selector de fotografii, acum poți explora galeria, căuta în bibliotecă și răsfoi albumele.',
          isAndroidOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Sortează albumele după numele fișierului',
          description:
              'Sortează fotografiile și videoclipurile din albume după numele fișierului.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Acum în indoneziană și suedeză',
          description:
              'Acum poți folosi Ente Photos în indoneziană sau suedeză.',
        ),
        ChangeLogEntryStrings(
          title: 'Copii de rezervă mai fiabile',
          description:
              'Am remediat câteva cazuri rare în care crearea copiilor de rezervă se putea bloca sau putea eșua.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Și alte îmbunătățiri!',
          description:
              'Editorul foto se deschide mai repede, decuparea în modul Original este mai fiabilă, iar amintirile din călătorii se repetă mai rar.',
        ),
      ],
    ),
    'ru': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Просмотрите старые фото и освободите место',
          description:
              'Листайте галерею и отмечайте для удаления фотографии, которые больше не хотите хранить.\n\nЭта функция находится в разделе Настройки → Освободить место → Old photos.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Обновлённое окно выбора фотографий',
          description:
              'Когда вы прикрепляете фото или видео в другом приложении через окно выбора фотографий Ente, теперь можно просматривать галерею, искать в медиатеке и открывать альбомы.',
          isAndroidOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Сортировка альбомов по имени файла',
          description: 'Сортируйте фото и видео в альбомах по имени файла.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Теперь на индонезийском и шведском',
          description:
              'Теперь Ente Photos можно использовать на индонезийском или шведском.',
        ),
        ChangeLogEntryStrings(
          title: 'Более надёжное резервное копирование',
          description:
              'Мы исправили несколько редких случаев, когда резервное копирование могло зависнуть или завершиться ошибкой.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'И не только!',
          description:
              'Фоторедактор открывается быстрее, обрезка в режиме Original работает надёжнее, а воспоминания о поездках реже повторяются.',
        ),
      ],
    ),
    'sv': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Gå igenom gamla foton och frigör utrymme',
          description:
              'Svep igenom galleriet och markera oönskade foton för radering.\n\nDu hittar funktionen under Inställningar → Frigör utrymme → Old photos.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Omarbetad fotoväljare',
          description:
              'När du bifogar foton eller videor i en annan app med Ente som fotoväljare kan du nu utforska galleriet, söka i biblioteket och bläddra i album.',
          isAndroidOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Sortera album efter filnamn',
          description: 'Sortera foton och videor i dina album efter filnamn.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Nu på indonesiska och svenska',
          description:
              'Du kan nu använda Ente Photos på indonesiska eller svenska.',
        ),
        ChangeLogEntryStrings(
          title: 'Mer tillförlitliga säkerhetskopior',
          description:
              'Vi har åtgärdat några ovanliga fall där säkerhetskopieringen kunde fastna eller misslyckas.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Och mer!',
          description:
              'Fotoredigeraren öppnas snabbare, beskärning i Original-läget är mer tillförlitlig och reseminnen upprepas mer sällan.',
        ),
      ],
    ),
    'tr': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Eski fotoğrafları gözden geçirin ve yer açın',
          description:
              'Galerinizde kaydırarak gezinin ve artık saklamak istemediğiniz fotoğrafları silmek üzere işaretleyin.\n\nBu özelliği Ayarlar → Boş alan → Old photos bölümünde bulabilirsiniz.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Yenilenen fotoğraf seçici',
          description:
              'Başka bir uygulamada Ente’yi fotoğraf seçici olarak kullanıp fotoğraf veya video eklerken artık galerinizi keşfedebilir, arşivinizde arama yapabilir ve albümlerinize göz atabilirsiniz.',
          isAndroidOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Albümleri dosya adına göre sıralayın',
          description:
              'Albümlerinizdeki fotoğraf ve videoları dosya adına göre sıralayın.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Artık Endonezce ve İsveççe',
          description:
              'Artık Ente Photos’u Endonezce veya İsveççe kullanabilirsiniz.',
        ),
        ChangeLogEntryStrings(
          title: 'Daha güvenilir yedekleme',
          description:
              'Yedeklemenin takılabildiği veya başarısız olabildiği bazı nadir durumları düzelttik.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Ve daha fazlası!',
          description:
              'Fotoğraf düzenleyici daha hızlı açılıyor, Original modunda kırpma daha güvenilir çalışıyor ve gezi anıları daha az tekrarlanıyor.',
        ),
      ],
    ),
    'uk': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Перегляньте старі фото та звільніть місце',
          description:
              'Гортайте галерею та позначайте для видалення фото, які більше не хочете зберігати.\n\nЦя функція доступна в розділі Налаштування → Звільнити місце → Old photos.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Оновлене вікно вибору фото',
          description:
              'Коли ви додаєте фото чи відео в іншому застосунку, використовуючи Ente для вибору фото, тепер можна гортати галерею, шукати в медіатеці та переглядати альбоми.',
          isAndroidOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Сортування альбомів за назвою файлу',
          description: 'Сортуйте фото й відео в альбомах за назвою файлу.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Тепер індонезійською та шведською',
          description:
              'Тепер Ente Photos можна використовувати індонезійською або шведською.',
        ),
        ChangeLogEntryStrings(
          title: 'Надійніше резервне копіювання',
          description:
              'Ми виправили кілька рідкісних випадків, коли резервне копіювання могло зависнути або завершитися помилкою.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'І не тільки!',
          description:
              'Редактор фото відкривається швидше, обрізання в режимі Original працює надійніше, а спогади про подорожі рідше повторюються.',
        ),
      ],
    ),
    'vi': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Xem lại ảnh cũ và giải phóng dung lượng',
          description:
              'Vuốt để xem thư viện và đánh dấu xóa những ảnh bạn không muốn giữ nữa.\n\nBạn có thể mở tính năng này trong Cài đặt → Giải phóng dung lượng → Old photos.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Trình chọn ảnh được làm mới',
          description:
              'Khi dùng Ente làm trình chọn ảnh để đính kèm ảnh hoặc video trong ứng dụng khác, giờ đây bạn có thể khám phá bộ sưu tập ảnh, tìm kiếm trong thư viện và duyệt album.',
          isAndroidOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Sắp xếp album theo tên tệp',
          description: 'Sắp xếp ảnh và video trong album theo tên tệp.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Đã có tiếng Indonesia và tiếng Thụy Điển',
          description:
              'Giờ đây bạn có thể dùng Ente Photos bằng tiếng Indonesia hoặc tiếng Thụy Điển.',
        ),
        ChangeLogEntryStrings(
          title: 'Sao lưu ổn định hơn',
          description:
              'Chúng tôi đã khắc phục một số trường hợp hiếm gặp khiến quá trình sao lưu có thể bị treo hoặc thất bại.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Và còn nữa!',
          description:
              'Trình chỉnh sửa ảnh mở nhanh hơn, cắt ảnh ở chế độ Original ổn định hơn và kỷ niệm chuyến đi ít bị lặp lại hơn.',
        ),
      ],
    ),
    'zh_CN': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: '整理旧照片，释放空间',
          description:
              '滑动浏览图库，将不想再保留的照片标记为待删除。\n\n在「设置 → 释放空间 → Old photos」中即可找到此功能。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '全新设计的照片选择器',
          description: '在其他应用中使用 Ente 作为照片选择器添加照片或视频时，现在可以浏览图库、搜索照片库和查看相册。',
          isAndroidOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '按文件名排序相册',
          description: '按文件名对相册里的照片和视频排序。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '现已支持印度尼西亚语和瑞典语',
          description: '现在可以使用印度尼西亚语或瑞典语版的 Ente Photos。',
        ),
        ChangeLogEntryStrings(
          title: '备份更可靠',
          description: '我们修复了少数可能导致备份卡住或失败的情况。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '还有更多！',
          description: '照片编辑器打开得更快，Original 模式下的裁剪更可靠，旅行回忆的重复显示也更少了。',
        ),
      ],
    ),
    'zh_TW': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: '整理舊照片，釋放空間',
          description:
              '滑動瀏覽圖片庫，將不想再保留的照片標記為待刪除。\n\n你可以在「設定 → 釋放空間 → Old photos」找到這項功能。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '重新設計的照片選擇器',
          description: '在其他應用程式中使用 Ente 作為照片選擇器附加照片或影片時，現在可以探索圖片庫、搜尋媒體庫和瀏覽相簿。',
          isAndroidOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '依檔名排序相簿',
          description: '依檔名排序相簿裡的照片和影片。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '現已支援印尼語和瑞典語',
          description: '現在可以使用印尼語或瑞典語版的 Ente Photos。',
        ),
        ChangeLogEntryStrings(
          title: '備份更可靠',
          description: '我們修正了少數可能導致備份卡住或失敗的情況。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '還有更多！',
          description: '照片編輯器開啟得更快，Original 模式下的裁切更可靠，旅行回憶也更少重複出現。',
        ),
      ],
    ),
  };
}

class ChangeLogEntryStrings {
  final String title;
  final String description;
  final bool isOnlineOnly;
  final bool isLocalGalleryOnly;
  final bool isAndroidOnly;
  final bool isIOSOnly;

  const ChangeLogEntryStrings({
    required this.title,
    required this.description,
    this.isOnlineOnly = false,
    this.isLocalGalleryOnly = false,
    this.isAndroidOnly = false,
    this.isIOSOnly = false,
  }) : assert(!(isOnlineOnly && isLocalGalleryOnly)),
       assert(!(isAndroidOnly && isIOSOnly));
}

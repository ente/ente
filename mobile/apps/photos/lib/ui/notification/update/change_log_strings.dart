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
          title: 'New look for your gallery',
          description:
              'See photos in their original proportions with the new mosaic layout.',
        ),
        ChangeLogEntryStrings(
          title: 'Pinch to change gallery layout',
          description:
              'You can now pinch in or out to switch layouts and choose how many photos fit on your screen.',
        ),
        ChangeLogEntryStrings(
          title: 'Image editor improvements',
          description:
              'Add text to your photos with a choice of fonts, colors, backgrounds, and alignment. You can now straighten tilted photos too.',
        ),
        ChangeLogEntryStrings(
          title: 'Fresh look for albums and more',
          description:
              'Redesigned albums and simpler menus for your photo actions.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Faster backup preparation',
          description:
              'Ente now prepares your photos and videos for upload more quickly.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Now in Korean',
          description: 'You can now use Ente Photos in Korean.',
        ),
        ChangeLogEntryStrings(
          title: 'And more!',
          description:
              'Memory Lane on your home screen, smoother photo transitions between gallery and viewer, clearer map markers, more reliable filters in hidden albums.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'And more!',
          description:
              'Memory Lane on your home screen, smoother photo transitions between gallery and viewer, clearer map markers.',
          isLocalGalleryOnly: true,
        ),
      ],
    ),
    'ca': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Nou aspecte per a la teva galeria',
          description:
              'Mira les fotos amb les proporcions originals amb el nou disseny en mosaic.',
        ),
        ChangeLogEntryStrings(
          title: 'Ajunta els dits per canviar la disposició de la galeria',
          description:
              'Ara pots ajuntar o separar dos dits per canviar de disposició i triar quantes fotos caben a la pantalla.',
        ),
        ChangeLogEntryStrings(
          title: 'Millores a l’editor d’imatges',
          description:
              'Afegeix text a les fotos i tria entre diversos tipus de lletra, colors, fons i opcions d’alineació. Ara també pots redreçar les fotos inclinades.',
        ),
        ChangeLogEntryStrings(
          title: 'Nou aspecte per als àlbums i més',
          description:
              'Àlbums redissenyats i menús més senzills per a les accions amb les fotos.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Preparació més ràpida de les còpies de seguretat',
          description:
              'Ara Ente prepara les fotos i els vídeos més ràpidament per pujar-los.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Ara en coreà',
          description: 'Ara pots fer servir Ente Photos en coreà.',
        ),
        ChangeLogEntryStrings(
          title: 'I més coses!',
          description:
              'Camí dels records a la pantalla d’inici, transicions de fotos més fluides entre la galeria i el visor, marcadors del mapa més clars, filtres més fiables als àlbums ocults.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'I més coses!',
          description:
              'Camí dels records a la pantalla d’inici, transicions de fotos més fluides entre la galeria i el visor, marcadors del mapa més clars.',
          isLocalGalleryOnly: true,
        ),
      ],
    ),
    'cs': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Nový vzhled vaší galerie',
          description:
              'Prohlížejte si fotografie v původních proporcích díky novému mozaikovému rozložení.',
        ),
        ChangeLogEntryStrings(
          title: 'Změna rozložení galerie stažením prstů',
          description:
              'Nyní můžete stažením nebo roztažením dvou prstů přepínat rozložení a zvolit, kolik fotografií se vejde na obrazovku.',
        ),
        ChangeLogEntryStrings(
          title: 'Vylepšení editoru obrázků',
          description:
              'Přidávejte k fotografiím text s výběrem písem, barev, pozadí a zarovnání. Nyní můžete také narovnat nakloněné fotografie.',
        ),
        ChangeLogEntryStrings(
          title: 'Nový vzhled alb a další změny',
          description:
              'Přepracovaná alba a jednodušší nabídky pro práci s fotografiemi.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Rychlejší příprava zálohování',
          description:
              'Ente nyní rychleji připravuje vaše fotografie a videa k nahrání.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Nyní i v korejštině',
          description: 'Ente Photos nyní můžete používat v korejštině.',
        ),
        ChangeLogEntryStrings(
          title: 'A mnohem více!',
          description:
              'Vzpomínání na domovské obrazovce, plynulejší přechody fotografií mezi galerií a prohlížečem, přehlednější značky na mapě, spolehlivější filtry ve skrytých albech.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'A mnohem více!',
          description:
              'Vzpomínání na domovské obrazovce, plynulejší přechody fotografií mezi galerií a prohlížečem, přehlednější značky na mapě.',
          isLocalGalleryOnly: true,
        ),
      ],
    ),
    'de': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Neuer Look für deine Galerie',
          description:
              'Sieh dir Fotos mit dem neuen Mosaiklayout in ihren ursprünglichen Proportionen an.',
        ),
        ChangeLogEntryStrings(
          title: 'Galerie-Layout durch Zusammenziehen zweier Finger ändern',
          description:
              'Du kannst jetzt zwei Finger zusammenziehen oder auseinanderziehen, um das Layout zu wechseln und auszuwählen, wie viele Fotos auf deinen Bildschirm passen.',
        ),
        ChangeLogEntryStrings(
          title: 'Verbesserungen im Bildeditor',
          description:
              'Füge deinen Fotos Text hinzu und wähle Schriftart, Farbe, Hintergrund und Ausrichtung. Jetzt kannst du auch schiefe Fotos gerade ausrichten.',
        ),
        ChangeLogEntryStrings(
          title: 'Frischer Look für Alben und mehr',
          description:
              'Neu gestaltete Alben und einfachere Menüs für deine Fotoaktionen.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Schnellere Vorbereitung der Datensicherung',
          description:
              'Ente bereitet deine Fotos und Videos jetzt schneller für das Hochladen vor.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Jetzt auf Koreanisch',
          description: 'Du kannst Ente Photos jetzt auf Koreanisch nutzen.',
        ),
        ChangeLogEntryStrings(
          title: 'Und mehr!',
          description:
              'Erinnerungen auf deinem Startbildschirm, flüssigere Fotoübergänge zwischen Galerie und Fotoansicht, deutlichere Kartenmarkierungen und zuverlässigere Filter in versteckten Alben.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Und mehr!',
          description:
              'Erinnerungen auf deinem Startbildschirm, flüssigere Fotoübergänge zwischen Galerie und Fotoansicht und deutlichere Kartenmarkierungen.',
          isLocalGalleryOnly: true,
        ),
      ],
    ),
    'es': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Nuevo aspecto para tu galería',
          description:
              'Ve las fotos con sus proporciones originales con el nuevo diseño de mosaico.',
        ),
        ChangeLogEntryStrings(
          title: 'Junta los dedos para cambiar el diseño de la galería',
          description:
              'Ahora puedes juntar o separar dos dedos para cambiar de diseño y elegir cuántas fotos caben en la pantalla.',
        ),
        ChangeLogEntryStrings(
          title: 'Mejoras en el editor de imágenes',
          description:
              'Añade texto a tus fotos y elige entre distintas fuentes, colores, fondos y opciones de alineación. Ahora también puedes enderezar las fotos inclinadas.',
        ),
        ChangeLogEntryStrings(
          title: 'Nuevo aspecto para los álbumes y más',
          description:
              'Álbumes rediseñados y menús más sencillos para las acciones con tus fotos.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Preparación más rápida de las copias de seguridad',
          description:
              'Ahora Ente prepara tus fotos y vídeos más rápido para subirlos.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Ahora en coreano',
          description: 'Ahora puedes usar Ente Photos en coreano.',
        ),
        ChangeLogEntryStrings(
          title: '¡Y mucho más!',
          description:
              'Jardín de recuerdos en tu pantalla de inicio, transiciones de fotos más fluidas entre la galería y el visor, marcadores del mapa más claros y filtros más fiables en los álbumes ocultos.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '¡Y mucho más!',
          description:
              'Jardín de recuerdos en tu pantalla de inicio, transiciones de fotos más fluidas entre la galería y el visor y marcadores del mapa más claros.',
          isLocalGalleryOnly: true,
        ),
      ],
    ),
    'fr': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Nouveau look pour votre galerie',
          description:
              'Affichez vos photos dans leurs proportions d’origine grâce à la nouvelle disposition en mosaïque.',
        ),
        ChangeLogEntryStrings(
          title: 'Pincez pour changer la disposition de la galerie',
          description:
              'Vous pouvez maintenant rapprocher ou écarter deux doigts pour changer de disposition et choisir combien de photos tiennent à l’écran.',
        ),
        ChangeLogEntryStrings(
          title: 'Améliorations de l’éditeur d’images',
          description:
              'Ajoutez du texte à vos photos en choisissant les polices, les couleurs, les arrière-plans et l’alignement. Vous pouvez désormais aussi redresser les photos inclinées.',
        ),
        ChangeLogEntryStrings(
          title: 'Nouveau look pour les albums et plus encore',
          description:
              'Des albums repensés et des menus simplifiés pour vos actions sur les photos.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Préparation des sauvegardes plus rapide',
          description:
              'Ente prépare désormais plus rapidement vos photos et vidéos pour leur envoi.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Désormais en coréen',
          description: 'Vous pouvez désormais utiliser Ente Photos en coréen.',
        ),
        ChangeLogEntryStrings(
          title: 'Et plus encore !',
          description:
              'Souvenirs sur votre écran d’accueil, transitions photo plus fluides entre la galerie et la visionneuse, repères plus clairs sur la carte et filtres plus fiables dans les albums masqués.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Et plus encore !',
          description:
              'Souvenirs sur votre écran d’accueil, transitions photo plus fluides entre la galerie et la visionneuse et repères plus clairs sur la carte.',
          isLocalGalleryOnly: true,
        ),
      ],
    ),
    'it': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Nuovo look per la tua galleria',
          description:
              'Guarda le foto nelle loro proporzioni originali con il nuovo layout a mosaico.',
        ),
        ChangeLogEntryStrings(
          title: 'Pizzica per cambiare il layout della galleria',
          description:
              'Ora puoi avvicinare o allontanare due dita per cambiare layout e scegliere quante foto entrano nello schermo.',
        ),
        ChangeLogEntryStrings(
          title: 'Miglioramenti all’editor di immagini',
          description:
              'Aggiungi testo alle tue foto scegliendo caratteri, colori, sfondi e allineamento. Ora puoi anche raddrizzare le foto inclinate.',
        ),
        ChangeLogEntryStrings(
          title: 'Nuovo look per gli album e non solo',
          description:
              'Album ridisegnati e menu più semplici per le azioni sulle tue foto.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Preparazione dei backup più rapida',
          description:
              'Ora Ente prepara più rapidamente le tue foto e i tuoi video per il caricamento.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Ora in coreano',
          description: 'Ora puoi usare Ente Photos in coreano.',
        ),
        ChangeLogEntryStrings(
          title: 'E molto altro!',
          description:
              'Volti nel tempo nella schermata iniziale, transizioni delle foto più fluide tra galleria e visualizzatore, indicatori più chiari sulla mappa e filtri più affidabili negli album nascosti.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'E molto altro!',
          description:
              'Volti nel tempo nella schermata iniziale, transizioni delle foto più fluide tra galleria e visualizzatore e indicatori più chiari sulla mappa.',
          isLocalGalleryOnly: true,
        ),
      ],
    ),
    'ja': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'ギャラリーが新しい見た目に',
          description: '新しいモザイクレイアウトで、写真を元の縦横比のまま表示できます。',
        ),
        ChangeLogEntryStrings(
          title: 'ピンチ操作でギャラリーのレイアウトを変更',
          description:
              '2本の指でつまんだり広げたりして、レイアウトを切り替えたり、画面に表示する写真の枚数を選んだりできるようになりました。',
        ),
        ChangeLogEntryStrings(
          title: '画像エディターの改善',
          description:
              'フォント、色、背景、配置を選んで写真にテキストを追加できます。傾いた写真をまっすぐに補正することもできるようになりました。',
        ),
        ChangeLogEntryStrings(
          title: 'アルバムなどのデザインを一新',
          description: 'アルバムを再デザインし、写真を操作するメニューをよりシンプルにしました。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'バックアップの準備がより高速に',
          description: 'Enteが写真や動画のアップロード準備をより速く行えるようになりました。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '韓国語に対応',
          description: 'Ente Photosを韓国語で使えるようになりました。',
        ),
        ChangeLogEntryStrings(
          title: 'さらに！',
          description:
              'ホーム画面にMemory Laneが登場。ギャラリーとビューアー間での写真の切り替えがよりスムーズになり、地図のマーカーが見やすく、非表示アルバムのフィルターもより確実に動作するようになりました。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'さらに！',
          description:
              'ホーム画面にMemory Laneが登場。ギャラリーとビューアー間での写真の切り替えがよりスムーズになり、地図のマーカーも見やすくなりました。',
          isLocalGalleryOnly: true,
        ),
      ],
    ),
    'ko': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: '새로워진 갤러리',
          description: '새로운 모자이크 레이아웃으로 사진을 원래 비율 그대로 감상하세요.',
        ),
        ChangeLogEntryStrings(
          title: '손가락을 오므려 갤러리 레이아웃 바꾸기',
          description: '이제 두 손가락을 오므리거나 벌려 레이아웃을 바꾸고 화면에 표시할 사진 수를 선택할 수 있어요.',
        ),
        ChangeLogEntryStrings(
          title: '이미지 편집기 개선',
          description:
              '글꼴, 색상, 배경, 정렬 방식을 선택해 사진에 텍스트를 추가하세요. 이제 기울어진 사진의 수평도 맞출 수 있어요.',
        ),
        ChangeLogEntryStrings(
          title: '새로워진 앨범과 메뉴',
          description: '앨범 디자인이 새로워지고 사진 작업 메뉴가 더 간편해졌어요.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '더 빨라진 백업 준비',
          description: '이제 Ente가 사진과 동영상의 업로드 준비를 더 빠르게 마쳐요.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '이제 한국어로도 사용하세요',
          description: '이제 Ente Photos를 한국어로 사용할 수 있어요.',
        ),
        ChangeLogEntryStrings(
          title: '그 밖에도!',
          description:
              '홈 화면의 추억의 길, 갤러리와 뷰어 사이의 더 부드러운 사진 전환, 더 명확한 지도 마커, 숨김 앨범에서 더 안정적으로 작동하는 필터를 만나보세요.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '그 밖에도!',
          description:
              '홈 화면의 추억의 길, 갤러리와 뷰어 사이의 더 부드러운 사진 전환, 더 명확한 지도 마커를 만나보세요.',
          isLocalGalleryOnly: true,
        ),
      ],
    ),
    'nl': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Nieuwe look voor je galerij',
          description:
              'Bekijk foto’s in hun oorspronkelijke verhoudingen met de nieuwe mozaïekindeling.',
        ),
        ChangeLogEntryStrings(
          title: 'Knijp om de galerijindeling te wijzigen',
          description:
              'Je kunt nu twee vingers naar elkaar toe of uit elkaar bewegen om van indeling te wisselen en te kiezen hoeveel foto’s op je scherm passen.',
        ),
        ChangeLogEntryStrings(
          title: 'Verbeteringen in de afbeeldingseditor',
          description:
              'Voeg tekst toe aan je foto’s met een keuze uit lettertypen, kleuren, achtergronden en uitlijning. Je kunt nu ook scheve foto’s rechtzetten.',
        ),
        ChangeLogEntryStrings(
          title: 'Frisse look voor albums en meer',
          description:
              'Vernieuwde albums en eenvoudigere menu’s voor je fotoacties.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Snellere voorbereiding van back-ups',
          description:
              'Ente bereidt je foto’s en video’s nu sneller voor op het uploaden.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Nu in het Koreaans',
          description: 'Je kunt Ente Photos nu in het Koreaans gebruiken.',
        ),
        ChangeLogEntryStrings(
          title: 'En meer!',
          description:
              'Herinneringen op je startscherm, vloeiendere foto-overgangen tussen galerij en fotoviewer, duidelijkere kaartmarkeringen en betrouwbaardere filters in verborgen albums.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'En meer!',
          description:
              'Herinneringen op je startscherm, vloeiendere foto-overgangen tussen galerij en fotoviewer en duidelijkere kaartmarkeringen.',
          isLocalGalleryOnly: true,
        ),
      ],
    ),
    'no': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Nytt utseende for galleriet ditt',
          description:
              'Se bilder i de opprinnelige proporsjonene med det nye mosaikkoppsettet.',
        ),
        ChangeLogEntryStrings(
          title: 'Endre gallerioppsettet ved å knipe',
          description:
              'Du kan nå føre to fingre sammen eller fra hverandre for å bytte oppsett og velge hvor mange bilder som får plass på skjermen.',
        ),
        ChangeLogEntryStrings(
          title: 'Forbedret bilderedigering',
          description:
              'Legg til tekst på bildene dine og velg skrifttyper, farger, bakgrunner og tekstjustering. Nå kan du også rette opp skjeve bilder.',
        ),
        ChangeLogEntryStrings(
          title: 'Friskt utseende for album og mer',
          description:
              'Album med nytt design og enklere menyer for handlinger med bildene dine.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Raskere klargjøring for sikkerhetskopiering',
          description:
              'Ente klargjør nå bildene og videoene dine raskere for opplasting.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Nå på koreansk',
          description: 'Du kan nå bruke Ente Photos på koreansk.',
        ),
        ChangeLogEntryStrings(
          title: 'Og mer!',
          description:
              'Memory Lane på startskjermen, jevnere bildeoverganger mellom galleriet og bildeviseren, tydeligere kartmarkører og mer pålitelige filtre i skjulte album.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Og mer!',
          description:
              'Memory Lane på startskjermen, jevnere bildeoverganger mellom galleriet og bildeviseren og tydeligere kartmarkører.',
          isLocalGalleryOnly: true,
        ),
      ],
    ),
    'pl': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Nowy wygląd Twojej galerii',
          description:
              'Oglądaj zdjęcia w oryginalnych proporcjach dzięki nowemu układowi mozaiki.',
        ),
        ChangeLogEntryStrings(
          title: 'Zsuń palce, aby zmienić układ galerii',
          description:
              'Teraz możesz zsuwać lub rozsuwać dwa palce, aby zmieniać układ i wybierać, ile zdjęć mieści się na ekranie.',
        ),
        ChangeLogEntryStrings(
          title: 'Ulepszenia edytora obrazów',
          description:
              'Dodawaj tekst do zdjęć, wybierając czcionki, kolory, tła i wyrównanie. Teraz możesz też prostować przekrzywione zdjęcia.',
        ),
        ChangeLogEntryStrings(
          title: 'Odświeżony wygląd albumów i nie tylko',
          description:
              'Przeprojektowane albumy i prostsze menu działań na zdjęciach.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Szybsze przygotowanie kopii zapasowych',
          description:
              'Ente teraz szybciej przygotowuje Twoje zdjęcia i filmy do przesłania.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Teraz po koreańsku',
          description: 'Możesz teraz korzystać z Ente Photos po koreańsku.',
        ),
        ChangeLogEntryStrings(
          title: 'I wiele więcej!',
          description:
              'Memory Lane na ekranie głównym, płynniejsze przejścia zdjęć między galerią a przeglądarką zdjęć, wyraźniejsze znaczniki na mapie i bardziej niezawodne filtry w ukrytych albumach.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'I wiele więcej!',
          description:
              'Memory Lane na ekranie głównym, płynniejsze przejścia zdjęć między galerią a przeglądarką zdjęć i wyraźniejsze znaczniki na mapie.',
          isLocalGalleryOnly: true,
        ),
      ],
    ),
    'pt_BR': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Novo visual para sua galeria',
          description:
              'Veja as fotos nas proporções originais com o novo layout em mosaico.',
        ),
        ChangeLogEntryStrings(
          title: 'Junte os dedos para mudar o layout da galeria',
          description:
              'Agora você pode juntar ou afastar dois dedos para mudar o layout e escolher quantas fotos cabem na tela.',
        ),
        ChangeLogEntryStrings(
          title: 'Melhorias no editor de imagens',
          description:
              'Adicione texto às suas fotos escolhendo fontes, cores, fundos e alinhamento. Agora você também pode endireitar fotos inclinadas.',
        ),
        ChangeLogEntryStrings(
          title: 'Novo visual para os álbuns e mais',
          description:
              'Álbuns redesenhados e menus mais simples para as ações nas suas fotos.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Preparação mais rápida do backup',
          description:
              'Agora o Ente prepara suas fotos e vídeos mais rapidamente para o envio.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Agora em coreano',
          description: 'Agora você pode usar o Ente Photos em coreano.',
        ),
        ChangeLogEntryStrings(
          title: 'E muito mais!',
          description:
              'Banner de Memória na sua tela inicial, transições de fotos mais suaves entre a galeria e o visualizador, marcadores mais claros no mapa e filtros mais confiáveis nos álbuns ocultos.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'E muito mais!',
          description:
              'Banner de Memória na sua tela inicial, transições de fotos mais suaves entre a galeria e o visualizador e marcadores mais claros no mapa.',
          isLocalGalleryOnly: true,
        ),
      ],
    ),
    'pt_PT': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Novo visual para a sua galeria',
          description:
              'Veja as fotografias nas proporções originais com o novo esquema em mosaico.',
        ),
        ChangeLogEntryStrings(
          title: 'Junte os dedos para mudar o esquema da galeria',
          description:
              'Agora pode juntar ou afastar dois dedos para mudar o esquema e escolher quantas fotografias cabem no ecrã.',
        ),
        ChangeLogEntryStrings(
          title: 'Melhorias no editor de imagens',
          description:
              'Adicione texto às suas fotografias, escolhendo tipos de letra, cores, fundos e alinhamento. Agora também pode endireitar fotografias inclinadas.',
        ),
        ChangeLogEntryStrings(
          title: 'Novo visual para os álbuns e mais',
          description:
              'Álbuns redesenhados e menus mais simples para as ações nas suas fotografias.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Preparação mais rápida das cópias de segurança',
          description:
              'O Ente prepara agora as suas fotografias e vídeos mais rapidamente para o carregamento.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Agora em coreano',
          description: 'Agora pode utilizar o Ente Photos em coreano.',
        ),
        ChangeLogEntryStrings(
          title: 'E muito mais!',
          description:
              'Memory Lane no seu ecrã principal, transições de fotografias mais suaves entre a galeria e o visualizador, marcadores mais claros no mapa e filtros mais fiáveis nos álbuns ocultos.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'E muito mais!',
          description:
              'Memory Lane no seu ecrã principal, transições de fotografias mais suaves entre a galeria e o visualizador e marcadores mais claros no mapa.',
          isLocalGalleryOnly: true,
        ),
      ],
    ),
    'ro': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Aspect nou pentru galeria ta',
          description:
              'Vezi fotografiile în proporțiile originale cu noul aranjament mozaic.',
        ),
        ChangeLogEntryStrings(
          title: 'Apropie degetele pentru a schimba aranjamentul galeriei',
          description:
              'Acum poți apropia sau depărta două degete pentru a schimba aranjamentul și a alege câte fotografii încap pe ecran.',
        ),
        ChangeLogEntryStrings(
          title: 'Îmbunătățiri ale editorului de imagini',
          description:
              'Adaugă text pe fotografii, alegând fonturi, culori, fundaluri și alinierea. Acum poți și să îndrepți fotografiile înclinate.',
        ),
        ChangeLogEntryStrings(
          title: 'Aspect nou pentru albume și nu numai',
          description:
              'Albume reproiectate și meniuri mai simple pentru acțiunile asupra fotografiilor.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Pregătirea mai rapidă a copiilor de rezervă',
          description:
              'Ente pregătește acum mai rapid fotografiile și videoclipurile tale pentru încărcare.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Acum în coreeană',
          description: 'Acum poți folosi Ente Photos în coreeană.',
        ),
        ChangeLogEntryStrings(
          title: 'Și altele!',
          description:
              'Memory Lane pe ecranul principal, tranziții mai fluide ale fotografiilor între galerie și vizualizator, marcaje mai clare pe hartă și filtre mai fiabile în albumele ascunse.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Și altele!',
          description:
              'Memory Lane pe ecranul principal, tranziții mai fluide ale fotografiilor între galerie și vizualizator și marcaje mai clare pe hartă.',
          isLocalGalleryOnly: true,
        ),
      ],
    ),
    'ru': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Новый облик вашей галереи',
          description:
              'Смотрите фотографии в исходных пропорциях с новой мозаичной раскладкой.',
        ),
        ChangeLogEntryStrings(
          title: 'Сведите пальцы, чтобы изменить раскладку галереи',
          description:
              'Теперь вы можете сводить или разводить два пальца, чтобы переключать раскладки и выбирать, сколько фотографий помещается на экране.',
        ),
        ChangeLogEntryStrings(
          title: 'Улучшения редактора изображений',
          description:
              'Добавляйте текст на фотографии, выбирая шрифты, цвета, фон и выравнивание. Теперь можно также выпрямлять наклонённые фотографии.',
        ),
        ChangeLogEntryStrings(
          title: 'Новый облик альбомов и не только',
          description:
              'Обновлённый дизайн альбомов и более простые меню действий с фотографиями.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Более быстрая подготовка резервного копирования',
          description:
              'Теперь Ente быстрее подготавливает ваши фотографии и видео к загрузке.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Теперь на корейском',
          description:
              'Теперь Ente Photos можно использовать на корейском языке.',
        ),
        ChangeLogEntryStrings(
          title: 'И многое другое!',
          description:
              'Линия воспоминаний на главном экране, более плавные переходы фотографий между галереей и экраном просмотра, более чёткие маркеры на карте и более надёжные фильтры в скрытых альбомах.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'И многое другое!',
          description:
              'Линия воспоминаний на главном экране, более плавные переходы фотографий между галереей и экраном просмотра и более чёткие маркеры на карте.',
          isLocalGalleryOnly: true,
        ),
      ],
    ),
    'tr': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Galeriniz için yeni görünüm',
          description:
              'Yeni mozaik düzeniyle fotoğraflarınızı özgün oranlarında görün.',
        ),
        ChangeLogEntryStrings(
          title: 'Galeri düzenini değiştirmek için parmaklarınızı birleştirin',
          description:
              'Artık iki parmağınızı birleştirerek veya ayırarak düzenler arasında geçiş yapabilir ve ekranınıza kaç fotoğraf sığacağını seçebilirsiniz.',
        ),
        ChangeLogEntryStrings(
          title: 'Görsel düzenleyicide iyileştirmeler',
          description:
              'Yazı tipi, renk, arka plan ve hizalama seçenekleriyle fotoğraflarınıza metin ekleyin. Artık eğik fotoğrafları da düzeltebilirsiniz.',
        ),
        ChangeLogEntryStrings(
          title: 'Albümler ve daha fazlası için yeni görünüm',
          description:
              'Yeniden tasarlanan albümler ve fotoğraf işlemleriniz için daha sade menüler.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Daha hızlı yedekleme hazırlığı',
          description:
              'Ente artık fotoğraf ve videolarınızı yüklemeye daha hızlı hazırlıyor.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Artık Korece de var',
          description: 'Ente Photos’u artık Korece kullanabilirsiniz.',
        ),
        ChangeLogEntryStrings(
          title: 'Ve daha fazlası!',
          description:
              'Ana ekranınızda Memory Lane, galeri ile görüntüleyici arasında daha akıcı fotoğraf geçişleri, daha belirgin harita işaretçileri ve gizli albümlerde daha güvenilir filtreler.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Ve daha fazlası!',
          description:
              'Ana ekranınızda Memory Lane, galeri ile görüntüleyici arasında daha akıcı fotoğraf geçişleri ve daha belirgin harita işaretçileri.',
          isLocalGalleryOnly: true,
        ),
      ],
    ),
    'uk': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Новий вигляд вашої галереї',
          description:
              'Переглядайте фотографії в оригінальних пропорціях із новою мозаїчною розкладкою.',
        ),
        ChangeLogEntryStrings(
          title: 'Зведіть пальці, щоб змінити розкладку галереї',
          description:
              'Тепер ви можете зводити або розводити два пальці, щоб перемикати розкладки й вибирати, скільки фотографій вміщується на екрані.',
        ),
        ChangeLogEntryStrings(
          title: 'Покращення редактора зображень',
          description:
              'Додавайте текст до фотографій, обираючи шрифти, кольори, тло й вирівнювання. Тепер можна також вирівнювати нахилені фотографії.',
        ),
        ChangeLogEntryStrings(
          title: 'Новий вигляд альбомів і не тільки',
          description:
              'Оновлений дизайн альбомів і простіші меню дій із фотографіями.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Швидша підготовка резервного копіювання',
          description:
              'Тепер Ente швидше готує ваші фотографії та відео до завантаження.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Тепер корейською',
          description:
              'Тепер Ente Photos можна використовувати корейською мовою.',
        ),
        ChangeLogEntryStrings(
          title: 'І не тільки!',
          description:
              'Лінія спогадів на головному екрані, плавніші переходи фотографій між галереєю та вікном перегляду, чіткіші позначки на мапі й надійніші фільтри в прихованих альбомах.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'І не тільки!',
          description:
              'Лінія спогадів на головному екрані, плавніші переходи фотографій між галереєю та вікном перегляду й чіткіші позначки на мапі.',
          isLocalGalleryOnly: true,
        ),
      ],
    ),
    'vi': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Diện mạo mới cho thư viện',
          description: 'Xem ảnh với tỷ lệ gốc bằng bố cục khảm mới.',
        ),
        ChangeLogEntryStrings(
          title: 'Chụm hai ngón tay để đổi bố cục thư viện',
          description:
              'Giờ đây, bạn có thể chụm hoặc tách hai ngón tay để chuyển đổi bố cục và chọn số ảnh hiển thị trên màn hình.',
        ),
        ChangeLogEntryStrings(
          title: 'Cải tiến trình chỉnh sửa ảnh',
          description:
              'Thêm văn bản vào ảnh với các lựa chọn về phông chữ, màu sắc, nền và căn chỉnh. Giờ đây, bạn cũng có thể làm thẳng những bức ảnh bị nghiêng.',
        ),
        ChangeLogEntryStrings(
          title: 'Diện mạo mới cho album và hơn thế nữa',
          description:
              'Album được thiết kế lại cùng các menu đơn giản hơn cho những thao tác với ảnh.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Chuẩn bị sao lưu nhanh hơn',
          description:
              'Ente giờ đây mất ít thời gian hơn để chuẩn bị ảnh và video của bạn cho việc tải lên.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Đã có tiếng Hàn',
          description:
              'Giờ đây, bạn có thể sử dụng Ente Photos bằng tiếng Hàn.',
        ),
        ChangeLogEntryStrings(
          title: 'Và còn nhiều hơn thế!',
          description:
              'Kỷ niệm trên màn hình chính, chuyển cảnh ảnh mượt mà hơn giữa thư viện và trình xem, các điểm đánh dấu trên bản đồ rõ ràng hơn, bộ lọc trong album ẩn hoạt động đáng tin cậy hơn.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Và còn nhiều hơn thế!',
          description:
              'Kỷ niệm trên màn hình chính, chuyển cảnh ảnh mượt mà hơn giữa thư viện và trình xem, các điểm đánh dấu trên bản đồ rõ ràng hơn.',
          isLocalGalleryOnly: true,
        ),
      ],
    ),
    'zh_CN': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: '图库焕然一新',
          description: '全新的拼贴布局让照片以原始比例显示。',
        ),
        ChangeLogEntryStrings(
          title: '双指捏合，更改图库布局',
          description: '现在，您可以通过双指捏合或张开来切换布局，并选择屏幕上显示的照片数量。',
        ),
        ChangeLogEntryStrings(
          title: '图片编辑器改进',
          description: '为照片添加文字，自由选择字体、颜色、背景和对齐方式。现在还可以拉直倾斜的照片。',
        ),
        ChangeLogEntryStrings(
          title: '相册等界面焕新',
          description: '重新设计的相册，以及更简洁的照片操作菜单。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '备份准备更快',
          description: 'Ente 现在能更快地为照片和视频做好上传准备。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '现已支持韩语',
          description: '现在可以使用韩语版 Ente Photos 了。',
        ),
        ChangeLogEntryStrings(
          title: '还有更多！',
          description: '主屏幕上的回忆长廊、图库与查看器之间更流畅的照片过渡、更清晰的地图标记，以及隐藏相册中更可靠的筛选功能。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '还有更多！',
          description: '主屏幕上的回忆长廊、图库与查看器之间更流畅的照片过渡，以及更清晰的地图标记。',
          isLocalGalleryOnly: true,
        ),
      ],
    ),
    'zh_TW': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: '圖片庫煥然一新',
          description: '全新的拼貼版面配置讓照片以原始比例顯示。',
        ),
        ChangeLogEntryStrings(
          title: '雙指捏合，變更圖片庫版面配置',
          description: '現在，你可以透過雙指捏合或張開來切換版面配置，並選擇螢幕上顯示的照片數量。',
        ),
        ChangeLogEntryStrings(
          title: '圖片編輯器改善',
          description: '為照片加入文字，自由選擇字型、顏色、背景和對齊方式。現在也可以拉直傾斜的照片。',
        ),
        ChangeLogEntryStrings(
          title: '相簿等介面煥新',
          description: '重新設計的相簿，以及更簡潔的照片操作選單。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '備份準備更快速',
          description: 'Ente 現在能更快地為照片和影片做好上傳準備。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '現已支援韓文',
          description: '現在可以使用韓文版 Ente Photos 了。',
        ),
        ChangeLogEntryStrings(
          title: '還有更多！',
          description: '主畫面上的懷舊小徑、圖片庫與檢視器之間更流暢的照片轉場、更清楚的地圖標記，以及隱藏相簿中更可靠的篩選功能。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '還有更多！',
          description: '主畫面上的懷舊小徑、圖片庫與檢視器之間更流暢的照片轉場，以及更清楚的地圖標記。',
          isLocalGalleryOnly: true,
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

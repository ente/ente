import 'dart:ui';

class ChangeLogStrings {
  final List<ChangeLogEntryStrings> entries;

  const ChangeLogStrings({required this.entries});

  static ChangeLogStrings? maybeForLocale(
    Locale locale, {
    bool isLocalGallery = false,
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

    final entries = isLocalGallery
        ? strings.entries
              .where((entry) => !entry.isOnlineOnly)
              .toList(growable: false)
        : strings.entries;
    return entries.isEmpty ? null : ChangeLogStrings(entries: entries);
  }

  static bool hasContentForLocale(
    Locale locale, {
    bool isLocalGallery = false,
  }) {
    return maybeForLocale(locale, isLocalGallery: isLocalGallery) != null;
  }

  static const Map<String, ChangeLogStrings> _translations = {
    'en': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Comments and reactions in memories',
          description:
              "Talk about shared memories with your loved ones, as you're reliving them.",
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Share memories, your way',
          description:
              'Choose exactly which photos and videos go into a memory before you share.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Photo viewer, polished',
          description:
              'The photo viewer and info sheet have been redesigned. Cleaner, nicer, easier to read.',
        ),
        ChangeLogEntryStrings(
          title: 'Text in photos, sharper',
          description:
              'Copying text from photos is now faster and more reliable. Long press to start selecting.',
        ),
        ChangeLogEntryStrings(
          title: 'Smarter caching',
          description:
              'Your photos stay quick to open while taking up less space on your device.',
        ),
        ChangeLogEntryStrings(
          title: 'and more!',
          description:
              'Faster and more reliable backups, smoother gallery browsing, better thumbnail loading and download reliability, improved text detection in photos, better avatar colors, fixes for crashes during background work, and lots of smaller polish across the app.',
          isOnlineOnly: true,
        ),
      ],
    ),
    'ca': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Comentaris i reaccions als records',
          description:
              'Parla dels records compartits amb les persones que estimes mentre els torneu a viure.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Comparteix els records a la teva manera',
          description:
              "Tria exactament quines fotos i vídeos formaran part d'un record abans de compartir-lo.",
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Visualitzador de fotos, renovat',
          description:
              "El visualitzador de fotos i el full d'informació s'han redissenyat. Més nets, agradables i fàcils de llegir.",
        ),
        ChangeLogEntryStrings(
          title: 'Text més nítid a les fotos',
          description:
              'Copiar text de les fotos ara és més ràpid i fiable. Mantén premut per començar a seleccionar.',
        ),
        ChangeLogEntryStrings(
          title: 'Memòria cau més intel·ligent',
          description:
              'Les fotos es continuen obrint ràpidament i ocupen menys espai al dispositiu.',
        ),
        ChangeLogEntryStrings(
          title: 'i molt més!',
          description:
              "Còpies de seguretat més ràpides i fiables, navegació més fluida per la galeria, millor càrrega de miniatures i baixades més fiables, detecció de text millorada a les fotos, millors colors d'avatar, correccions d'errors durant les tasques en segon pla i molts petits retocs a tota l'aplicació.",
          isOnlineOnly: true,
        ),
      ],
    ),
    'cs': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Komentáře a reakce ve vzpomínkách',
          description:
              'Povídejte si o sdílených vzpomínkách se svými blízkými, zatímco je znovu prožíváte.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Sdílejte vzpomínky po svém',
          description:
              'Před sdílením si přesně vyberte, které fotky a videa budou ve vzpomínce.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Vyladěný prohlížeč fotek',
          description:
              'Prohlížeč fotek a informační panel jsme přepracovali. Jsou přehlednější, hezčí a lépe se čtou.',
        ),
        ChangeLogEntryStrings(
          title: 'Ostřejší text ve fotkách',
          description:
              'Kopírování textu z fotek je nyní rychlejší a spolehlivější. Dlouhým stisknutím zahájíte výběr.',
        ),
        ChangeLogEntryStrings(
          title: 'Chytřejší ukládání do mezipaměti',
          description:
              'Fotky se otevírají rychle a zabírají v zařízení méně místa.',
        ),
        ChangeLogEntryStrings(
          title: 'a ještě víc!',
          description:
              'Rychlejší a spolehlivější zálohování, plynulejší procházení galerie, lepší načítání náhledů a spolehlivější stahování, lepší rozpoznávání textu ve fotkách, lepší barvy avatarů, opravy pádů během práce na pozadí a spousta dalších drobných vylepšení v celé aplikaci.',
          isOnlineOnly: true,
        ),
      ],
    ),
    'de': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Kommentare und Reaktionen in Erinnerungen',
          description:
              'Unterhalte dich mit deinen Liebsten über geteilte Erinnerungen, während ihr sie gemeinsam noch einmal erlebt.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Erinnerungen teilen, wie du möchtest',
          description:
              'Wähle vor dem Teilen genau aus, welche Fotos und Videos in einer Erinnerung enthalten sind.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Fotoanzeige, jetzt noch besser',
          description:
              'Die Fotoanzeige und das Infoblatt wurden neu gestaltet. Aufgeräumter, schöner und leichter zu lesen.',
        ),
        ChangeLogEntryStrings(
          title: 'Text in Fotos, klarer',
          description:
              'Das Kopieren von Text aus Fotos ist jetzt schneller und zuverlässiger. Halte zum Auswählen länger gedrückt.',
        ),
        ChangeLogEntryStrings(
          title: 'Intelligenteres Caching',
          description:
              'Deine Fotos lassen sich weiterhin schnell öffnen und belegen dabei weniger Speicherplatz auf deinem Gerät.',
        ),
        ChangeLogEntryStrings(
          title: 'und vieles mehr!',
          description:
              'Schnellere und zuverlässigere Backups, flüssigeres Durchsuchen der Galerie, besseres Laden von Miniaturansichten und zuverlässigere Downloads, verbesserte Texterkennung in Fotos, bessere Avatarfarben, Korrekturen für Abstürze bei Hintergrundaufgaben und viele kleinere Verbesserungen in der gesamten App.',
          isOnlineOnly: true,
        ),
      ],
    ),
    'es': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Comentarios y reacciones en los recuerdos',
          description:
              'Habla sobre los recuerdos compartidos con tus seres queridos mientras los revives.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Comparte recuerdos a tu manera',
          description:
              'Elige exactamente qué fotos y vídeos incluir en un recuerdo antes de compartirlo.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Visor de fotos, renovado',
          description:
              'Se han rediseñado el visor de fotos y la hoja de información. Más limpios, agradables y fáciles de leer.',
        ),
        ChangeLogEntryStrings(
          title: 'Texto más nítido en las fotos',
          description:
              'Copiar texto de las fotos ahora es más rápido y fiable. Mantén pulsado para empezar a seleccionar.',
        ),
        ChangeLogEntryStrings(
          title: 'Caché más inteligente',
          description:
              'Tus fotos siguen abriéndose rápidamente y ocupan menos espacio en el dispositivo.',
        ),
        ChangeLogEntryStrings(
          title: '¡y mucho más!',
          description:
              'Copias de seguridad más rápidas y fiables, navegación más fluida por la galería, mejor carga de miniaturas y descargas más fiables, detección de texto mejorada en las fotos, mejores colores de avatar, correcciones de fallos durante tareas en segundo plano y muchos pequeños retoques en toda la app.',
          isOnlineOnly: true,
        ),
      ],
    ),
    'fr': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Commentaires et réactions dans les souvenirs',
          description:
              'Discutez des souvenirs partagés avec vos proches tout en les revivant.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Partagez vos souvenirs à votre façon',
          description:
              'Choisissez précisément les photos et vidéos à inclure dans un souvenir avant de le partager.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Visionneuse de photos peaufinée',
          description:
              'La visionneuse de photos et la fiche d’informations ont été repensées. Plus claires, plus agréables et plus faciles à lire.',
        ),
        ChangeLogEntryStrings(
          title: 'Texte plus net dans les photos',
          description:
              'La copie de texte depuis les photos est désormais plus rapide et plus fiable. Appuyez longuement pour commencer la sélection.',
        ),
        ChangeLogEntryStrings(
          title: 'Mise en cache plus intelligente',
          description:
              'Vos photos restent rapides à ouvrir tout en occupant moins d’espace sur votre appareil.',
        ),
        ChangeLogEntryStrings(
          title: 'et bien plus encore !',
          description:
              'Des sauvegardes plus rapides et plus fiables, une navigation plus fluide dans la galerie, un meilleur chargement des miniatures et des téléchargements plus fiables, une meilleure détection du texte dans les photos, de meilleures couleurs d’avatar, des correctifs pour les plantages pendant les tâches en arrière-plan et de nombreuses petites améliorations dans toute l’app.',
          isOnlineOnly: true,
        ),
      ],
    ),
    'it': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Commenti e reazioni nei ricordi',
          description:
              'Parla dei ricordi condivisi con le persone che ami mentre li rivivi.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Condividi i ricordi a modo tuo',
          description:
              'Scegli esattamente quali foto e video inserire in un ricordo prima di condividerlo.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Visualizzatore di foto perfezionato',
          description:
              'Il visualizzatore di foto e la scheda delle informazioni sono stati riprogettati. Più ordinati, gradevoli e facili da leggere.',
        ),
        ChangeLogEntryStrings(
          title: 'Testo nelle foto più nitido',
          description:
              'Copiare il testo dalle foto ora è più veloce e affidabile. Tieni premuto per iniziare la selezione.',
        ),
        ChangeLogEntryStrings(
          title: 'Cache più intelligente',
          description:
              'Le tue foto restano rapide da aprire e occupano meno spazio sul dispositivo.',
        ),
        ChangeLogEntryStrings(
          title: 'e molto altro!',
          description:
              'Backup più veloci e affidabili, navigazione più fluida nella galleria, caricamento migliore delle miniature e download più affidabili, rilevamento del testo nelle foto migliorato, colori degli avatar migliori, correzioni per gli arresti anomali durante le attività in background e tanti piccoli miglioramenti in tutta l’app.',
          isOnlineOnly: true,
        ),
      ],
    ),
    'ja': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: '思い出でのコメントとリアクション',
          description: '大切な人と共有した思い出を振り返りながら、会話を楽しめます。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '思い出を自分らしく共有',
          description: '共有する前に、思い出に含める写真や動画を自由に選べます。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '写真ビューアーをさらに使いやすく',
          description: '写真ビューアーと情報シートを再設計しました。よりすっきり、美しく、読みやすくなりました。',
        ),
        ChangeLogEntryStrings(
          title: '写真内のテキストをより鮮明に',
          description: '写真からのテキストコピーが、より高速で確実になりました。長押しして選択を開始できます。',
        ),
        ChangeLogEntryStrings(
          title: 'よりスマートなキャッシュ',
          description: '写真をすばやく開ける快適さはそのままに、デバイスの使用容量を抑えます。',
        ),
        ChangeLogEntryStrings(
          title: 'さらに多くの改善！',
          description:
              'バックアップの高速化と信頼性向上、ギャラリー閲覧のなめらかさ向上、サムネイル読み込みとダウンロードの信頼性向上、写真内のテキスト検出の改善、アバターの色の改善、バックグラウンド処理中のクラッシュ修正など、アプリ全体に多くの細かな改善を加えました。',
          isOnlineOnly: true,
        ),
      ],
    ),
    'nl': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Opmerkingen en reacties in herinneringen',
          description:
              'Praat met je dierbaren over gedeelde herinneringen terwijl jullie ze opnieuw beleven.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Deel herinneringen op jouw manier',
          description:
              "Kies precies welke foto's en video's in een herinnering komen voordat je deze deelt.",
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Fotoviewer, verfijnd',
          description:
              'De fotoviewer en het informatieblad zijn opnieuw ontworpen. Rustiger, mooier en makkelijker te lezen.',
        ),
        ChangeLogEntryStrings(
          title: "Tekst in foto's, scherper",
          description:
              "Tekst uit foto's kopiëren is nu sneller en betrouwbaarder. Houd ingedrukt om te beginnen met selecteren.",
        ),
        ChangeLogEntryStrings(
          title: 'Slimmere caching',
          description:
              "Je foto's blijven snel openen en nemen minder ruimte in op je apparaat.",
        ),
        ChangeLogEntryStrings(
          title: 'en meer!',
          description:
              "Snellere en betrouwbaardere back-ups, soepeler bladeren door de galerij, beter laden van miniaturen en betrouwbaardere downloads, verbeterde tekstherkenning in foto's, betere avatarkleuren, oplossingen voor crashes tijdens achtergrondtaken en veel kleinere verbeteringen in de hele app.",
          isOnlineOnly: true,
        ),
      ],
    ),
    'no': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Kommentarer og reaksjoner i minner',
          description:
              'Snakk om delte minner med dem du er glad i, mens dere opplever dem på nytt.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Del minner på din måte',
          description:
              'Velg nøyaktig hvilke bilder og videoer som skal være med i et minne før du deler det.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'En mer polert bildevisning',
          description:
              'Bildevisningen og informasjonsarket har fått ny design. Renere, finere og enklere å lese.',
        ),
        ChangeLogEntryStrings(
          title: 'Skarpere tekst i bilder',
          description:
              'Kopiering av tekst fra bilder er nå raskere og mer pålitelig. Trykk og hold for å begynne å velge.',
        ),
        ChangeLogEntryStrings(
          title: 'Smartere hurtigbufring',
          description:
              'Bildene dine åpnes fortsatt raskt, samtidig som de tar mindre plass på enheten.',
        ),
        ChangeLogEntryStrings(
          title: 'og mer!',
          description:
              'Raskere og mer pålitelige sikkerhetskopier, jevnere galleriblaing, bedre innlasting av miniatyrbilder og mer pålitelige nedlastinger, forbedret tekstgjenkjenning i bilder, bedre avatarfarger, rettelser for krasj under bakgrunnsarbeid og mange små forbedringer i hele appen.',
          isOnlineOnly: true,
        ),
      ],
    ),
    'pl': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Komentarze i reakcje we wspomnieniach',
          description:
              'Rozmawiaj z bliskimi o udostępnionych wspomnieniach, przeżywając je ponownie.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Udostępniaj wspomnienia po swojemu',
          description:
              'Przed udostępnieniem wybierz dokładnie, które zdjęcia i filmy znajdą się we wspomnieniu.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Dopracowana przeglądarka zdjęć',
          description:
              'Przeglądarka zdjęć i panel informacji zostały przeprojektowane. Są przejrzystsze, ładniejsze i łatwiejsze do odczytania.',
        ),
        ChangeLogEntryStrings(
          title: 'Wyraźniejszy tekst na zdjęciach',
          description:
              'Kopiowanie tekstu ze zdjęć jest teraz szybsze i bardziej niezawodne. Naciśnij i przytrzymaj, aby rozpocząć zaznaczanie.',
        ),
        ChangeLogEntryStrings(
          title: 'Inteligentniejsze buforowanie',
          description:
              'Zdjęcia nadal otwierają się szybko, zajmując mniej miejsca na urządzeniu.',
        ),
        ChangeLogEntryStrings(
          title: 'i wiele więcej!',
          description:
              'Szybsze i bardziej niezawodne kopie zapasowe, płynniejsze przeglądanie galerii, lepsze wczytywanie miniatur i bardziej niezawodne pobieranie, ulepszone wykrywanie tekstu na zdjęciach, lepsze kolory awatarów, poprawki awarii podczas pracy w tle oraz wiele drobnych ulepszeń w całej aplikacji.',
          isOnlineOnly: true,
        ),
      ],
    ),
    'pt_BR': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Comentários e reações nas memórias',
          description:
              'Converse sobre memórias compartilhadas com quem você ama enquanto vocês as revivem.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Compartilhe memórias do seu jeito',
          description:
              'Escolha exatamente quais fotos e vídeos entram em uma memória antes de compartilhá-la.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Visualizador de fotos aprimorado',
          description:
              'O visualizador de fotos e a tela de informações foram redesenhados. Mais limpos, bonitos e fáceis de ler.',
        ),
        ChangeLogEntryStrings(
          title: 'Texto mais nítido nas fotos',
          description:
              'Copiar texto das fotos agora está mais rápido e confiável. Toque e segure para começar a selecionar.',
        ),
        ChangeLogEntryStrings(
          title: 'Cache mais inteligente',
          description:
              'Suas fotos continuam abrindo rapidamente e ocupam menos espaço no dispositivo.',
        ),
        ChangeLogEntryStrings(
          title: 'e muito mais!',
          description:
              'Backups mais rápidos e confiáveis, navegação mais fluida na galeria, melhor carregamento de miniaturas e downloads mais confiáveis, melhor detecção de texto nas fotos, melhores cores de avatar, correções de falhas durante tarefas em segundo plano e muitos pequenos aprimoramentos em todo o app.',
          isOnlineOnly: true,
        ),
      ],
    ),
    'pt_PT': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Comentários e reações nas memórias',
          description:
              'Converse sobre memórias partilhadas com quem mais gosta enquanto as revive.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Partilhe memórias à sua maneira',
          description:
              'Escolha exatamente quais fotografias e vídeos entram numa memória antes de a partilhar.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Visualizador de fotografias aperfeiçoado',
          description:
              'O visualizador de fotografias e a folha de informações foram redesenhados. Mais simples, agradáveis e fáceis de ler.',
        ),
        ChangeLogEntryStrings(
          title: 'Texto mais nítido nas fotografias',
          description:
              'Copiar texto das fotografias é agora mais rápido e fiável. Toque sem soltar para começar a selecionar.',
        ),
        ChangeLogEntryStrings(
          title: 'Armazenamento em cache mais inteligente',
          description:
              'As suas fotografias continuam a abrir rapidamente e ocupam menos espaço no dispositivo.',
        ),
        ChangeLogEntryStrings(
          title: 'e muito mais!',
          description:
              'Cópias de segurança mais rápidas e fiáveis, navegação mais fluida na galeria, melhor carregamento de miniaturas e transferências mais fiáveis, melhor deteção de texto nas fotografias, melhores cores de avatar, correções de falhas durante tarefas em segundo plano e muitos pequenos aperfeiçoamentos em toda a aplicação.',
          isOnlineOnly: true,
        ),
      ],
    ),
    'ro': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Comentarii și reacții în amintiri',
          description:
              'Vorbește despre amintirile partajate cu cei dragi, în timp ce le retrăiți.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Partajează amintirile în felul tău',
          description:
              'Alege exact ce fotografii și videoclipuri intră într-o amintire înainte de a o partaja.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Vizualizator de fotografii îmbunătățit',
          description:
              'Vizualizatorul de fotografii și panoul de informații au fost reproiectate. Mai clare, mai plăcute și mai ușor de citit.',
        ),
        ChangeLogEntryStrings(
          title: 'Text mai clar în fotografii',
          description:
              'Copierea textului din fotografii este acum mai rapidă și mai fiabilă. Apasă lung pentru a începe selectarea.',
        ),
        ChangeLogEntryStrings(
          title: 'Stocare în cache mai inteligentă',
          description:
              'Fotografiile se deschid în continuare rapid și ocupă mai puțin spațiu pe dispozitiv.',
        ),
        ChangeLogEntryStrings(
          title: 'și multe altele!',
          description:
              'Copii de siguranță mai rapide și mai fiabile, navigare mai fluidă în galerie, încărcare mai bună a miniaturilor și descărcări mai fiabile, detectare îmbunătățită a textului din fotografii, culori mai bune pentru avatare, remedieri pentru blocări în timpul activităților din fundal și multe mici îmbunătățiri în întreaga aplicație.',
          isOnlineOnly: true,
        ),
      ],
    ),
    'ru': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Комментарии и реакции в воспоминаниях',
          description:
              'Обсуждайте общие воспоминания с близкими, заново переживая их вместе.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Делитесь воспоминаниями по-своему',
          description:
              'Перед публикацией выберите, какие именно фото и видео войдут в воспоминание.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Обновлённый просмотр фото',
          description:
              'Мы переработали просмотр фото и панель сведений. Они стали чище, приятнее и удобнее для чтения.',
        ),
        ChangeLogEntryStrings(
          title: 'Более чёткий текст на фото',
          description:
              'Копировать текст с фотографий теперь быстрее и надёжнее. Нажмите и удерживайте, чтобы начать выделение.',
        ),
        ChangeLogEntryStrings(
          title: 'Умнее кэширование',
          description:
              'Фотографии по-прежнему быстро открываются, занимая меньше места на устройстве.',
        ),
        ChangeLogEntryStrings(
          title: 'и не только!',
          description:
              'Более быстрое и надёжное резервное копирование, плавный просмотр галереи, улучшенная загрузка миниатюр и надёжность скачивания, более точное распознавание текста на фото, улучшенные цвета аватаров, исправления сбоев во время фоновой работы и множество небольших улучшений во всём приложении.',
          isOnlineOnly: true,
        ),
      ],
    ),
    'tr': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Anılarda yorumlar ve tepkiler',
          description:
              'Paylaşılan anıları yeniden yaşarken sevdiklerinizle onlar hakkında konuşun.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Anıları istediğiniz gibi paylaşın',
          description:
              'Paylaşmadan önce bir anıya hangi fotoğraf ve videoların ekleneceğini tam olarak seçin.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Daha şık fotoğraf görüntüleyici',
          description:
              'Fotoğraf görüntüleyici ve bilgi sayfası yeniden tasarlandı. Daha sade, güzel ve okunması kolay.',
        ),
        ChangeLogEntryStrings(
          title: 'Fotoğraflardaki metin artık daha net',
          description:
              'Fotoğraflardan metin kopyalamak artık daha hızlı ve güvenilir. Seçmeye başlamak için basılı tutun.',
        ),
        ChangeLogEntryStrings(
          title: 'Daha akıllı önbellekleme',
          description:
              'Fotoğraflarınız hızlı açılmaya devam ederken cihazınızda daha az yer kaplar.',
        ),
        ChangeLogEntryStrings(
          title: 've daha fazlası!',
          description:
              'Daha hızlı ve güvenilir yedeklemeler, daha akıcı galeri gezintisi, daha iyi küçük resim yükleme ve indirme güvenilirliği, fotoğraflarda geliştirilmiş metin algılama, daha iyi avatar renkleri, arka plan çalışmaları sırasında oluşan çökmeler için düzeltmeler ve uygulama genelinde birçok küçük iyileştirme.',
          isOnlineOnly: true,
        ),
      ],
    ),
    'uk': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Коментарі та реакції у спогадах',
          description:
              'Обговорюйте спільні спогади з близькими, переживаючи їх знову.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Діліться спогадами по-своєму',
          description:
              'Перед публікацією виберіть, які саме фото й відео увійдуть до спогаду.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Оновлений переглядач фото',
          description:
              'Ми оновили переглядач фото та інформаційну панель. Вони стали охайнішими, приємнішими й легшими для читання.',
        ),
        ChangeLogEntryStrings(
          title: 'Чіткіший текст на фото',
          description:
              'Копіювати текст із фотографій тепер швидше й надійніше. Натисніть і утримуйте, щоб почати виділення.',
        ),
        ChangeLogEntryStrings(
          title: 'Розумніше кешування',
          description:
              'Фотографії, як і раніше, відкриваються швидко, займаючи менше місця на пристрої.',
        ),
        ChangeLogEntryStrings(
          title: 'і не тільки!',
          description:
              'Швидше та надійніше резервне копіювання, плавніший перегляд галереї, краще завантаження мініатюр і надійніше завантаження файлів, покращене розпізнавання тексту на фото, кращі кольори аватарів, виправлення збоїв під час фонової роботи та багато невеликих покращень у всьому застосунку.',
          isOnlineOnly: true,
        ),
      ],
    ),
    'vi': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Bình luận và cảm xúc trong kỷ niệm',
          description:
              'Trò chuyện về những kỷ niệm đã chia sẻ với người thân yêu khi cùng nhau sống lại những khoảnh khắc ấy.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Chia sẻ kỷ niệm theo cách của bạn',
          description:
              'Chọn chính xác ảnh và video sẽ có trong một kỷ niệm trước khi chia sẻ.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Trình xem ảnh được trau chuốt',
          description:
              'Trình xem ảnh và bảng thông tin đã được thiết kế lại. Gọn gàng, đẹp mắt và dễ đọc hơn.',
        ),
        ChangeLogEntryStrings(
          title: 'Văn bản trong ảnh rõ nét hơn',
          description:
              'Sao chép văn bản từ ảnh giờ nhanh hơn và đáng tin cậy hơn. Nhấn giữ để bắt đầu chọn.',
        ),
        ChangeLogEntryStrings(
          title: 'Bộ nhớ đệm thông minh hơn',
          description:
              'Ảnh vẫn mở nhanh trong khi chiếm ít dung lượng hơn trên thiết bị.',
        ),
        ChangeLogEntryStrings(
          title: 'và nhiều hơn nữa!',
          description:
              'Sao lưu nhanh và đáng tin cậy hơn, duyệt thư viện mượt mà hơn, tải hình thu nhỏ tốt hơn và tải xuống đáng tin cậy hơn, cải thiện khả năng phát hiện văn bản trong ảnh, màu hình đại diện đẹp hơn, sửa lỗi treo ứng dụng khi chạy tác vụ nền cùng nhiều cải tiến nhỏ khác trong toàn bộ ứng dụng.',
          isOnlineOnly: true,
        ),
      ],
    ),
    'zh_CN': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: '回忆中的评论和回应',
          description: '与亲友一起重温共享回忆，边看边聊。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '按你的方式分享回忆',
          description: '分享前，精确选择要加入回忆的照片和视频。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '更精致的照片查看器',
          description: '照片查看器和信息面板已重新设计。界面更简洁、更美观，也更易读。',
        ),
        ChangeLogEntryStrings(
          title: '照片中的文字更清晰',
          description: '现在，从照片中复制文字更快、更可靠。长按即可开始选择。',
        ),
        ChangeLogEntryStrings(
          title: '更智能的缓存',
          description: '照片依然能快速打开，同时占用更少的设备空间。',
        ),
        ChangeLogEntryStrings(
          title: '还有更多！',
          description:
              '备份更快、更可靠，浏览图库更流畅，缩略图加载更好，下载更可靠，照片文字检测更准确，头像颜色更协调，修复后台任务期间的崩溃问题，以及贯穿整个应用的众多细节优化。',
          isOnlineOnly: true,
        ),
      ],
    ),
  };
}

class ChangeLogEntryStrings {
  final String title;
  final String description;
  final bool isOnlineOnly;

  const ChangeLogEntryStrings({
    required this.title,
    required this.description,
    this.isOnlineOnly = false,
  });
}

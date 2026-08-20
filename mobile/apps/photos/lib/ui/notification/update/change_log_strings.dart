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

    final entries = strings.entries
        .where(
          (entry) =>
              isLocalGallery ? !entry.isOnlineOnly : !entry.isLocalGalleryOnly,
        )
        .toList(growable: false);
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
          title: 'Library Sharing',
          description:
              'Share your current and future albums with family members automatically. Head to Settings → Family, pick a member, and tap Share albums. New albums are included as you create them.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Album descriptions',
          description:
              'Give an album a description alongside its name and cover photo. Descriptions travel with your shared links, so anyone opening one sees the context you added.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Faster on big libraries',
          description:
              'Search, Smart Memories, the map, and timeline scrolling are all substantially quicker if you have a large library. Map clustering alone is 2–3x faster.',
        ),
        ChangeLogEntryStrings(
          title: 'Backups you can watch',
          description:
              'Backup Status now shows per-file progress, and large multipart uploads are more reliable.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Selecting text in photos',
          description:
              'Controls stay reachable while you select, and tapping selected text clears it.',
        ),
        ChangeLogEntryStrings(
          title: 'A tidier selection menu',
          description:
              'The actions in the selection bar are ordered by how often you reach for them, and the share icon now matches your platform.',
        ),
      ],
    ),
    'ca': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Compartició de la biblioteca',
          description:
              "Comparteix automàticament els àlbums actuals i futurs amb els membres de la família. Ves a Configuració → Família, tria un membre i toca Comparteix àlbums. Els àlbums nous s'hi inclouran a mesura que els creïs.",
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Descripcions dels àlbums',
          description:
              "Dona context a un àlbum amb una descripció, a més del nom i la foto de portada. Les descripcions s'inclouen als enllaços compartits perquè tothom qui n'obri un vegi el context que hi has afegit.",
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Més ràpid amb biblioteques grans',
          description:
              "La cerca, els Records intel·ligents, el mapa i el desplaçament per la línia de temps són molt més ràpids si tens una biblioteca gran. Només l'agrupació del mapa és entre 2 i 3 vegades més ràpida.",
        ),
        ChangeLogEntryStrings(
          title: 'Còpies de seguretat que pots seguir',
          description:
              "L'Estat de la còpia de seguretat ara mostra el progrés de cada fitxer, i les pujades grans en diverses parts són més fiables.",
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Selecció de text a les fotos',
          description:
              'Els controls continuen accessibles mentre selecciones text, i tocar el text seleccionat en suprimeix la selecció.',
        ),
        ChangeLogEntryStrings(
          title: 'Un menú de selecció més ordenat',
          description:
              'Les accions de la barra de selecció s’ordenen segons la freqüència amb què les utilitzes, i la icona de compartir ara coincideix amb la de la teva plataforma.',
        ),
      ],
    ),
    'cs': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Sdílení knihovny',
          description:
              'Automaticky sdílejte svá současná i budoucí alba s členy rodiny. Přejděte do Nastavení → Rodina, vyberte člena a klepněte na Sdílet alba. Nová alba se zahrnou hned, jak je vytvoříte.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Popisy alb',
          description:
              'K názvu a titulní fotce alba teď můžete přidat i popis. Popisy se přenášejí do sdílených odkazů, takže každý, kdo je otevře, uvidí kontext, který jste přidali.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Rychlejší u velkých knihoven',
          description:
              'Vyhledávání, Chytré vzpomínky, mapa i posouvání časové osy jsou u velkých knihoven výrazně rychlejší. Samotné seskupování na mapě je 2–3× rychlejší.',
        ),
        ChangeLogEntryStrings(
          title: 'Zálohování pod dohledem',
          description:
              'Stav zálohování teď zobrazuje průběh jednotlivých souborů a velká vícedílná nahrávání jsou spolehlivější.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Výběr textu ve fotkách',
          description:
              'Ovládací prvky zůstávají při výběru textu dostupné a klepnutí na vybraný text výběr zruší.',
        ),
        ChangeLogEntryStrings(
          title: 'Přehlednější nabídka výběru',
          description:
              'Akce na liště výběru jsou seřazené podle toho, jak často je používáte, a ikona sdílení teď odpovídá vaší platformě.',
        ),
      ],
    ),
    'de': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Bibliothek teilen',
          description:
              'Teile deine aktuellen und zukünftigen Alben automatisch mit Familienmitgliedern. Gehe zu Einstellungen → Familie, wähle ein Mitglied aus und tippe auf Alben teilen. Neue Alben werden beim Erstellen automatisch einbezogen.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Albumbeschreibungen',
          description:
              'Gib einem Album zusätzlich zu Name und Titelbild eine Beschreibung. Beschreibungen werden über deine geteilten Links mitgegeben, sodass alle, die einen Link öffnen, den von dir hinzugefügten Kontext sehen.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Schneller bei großen Bibliotheken',
          description:
              'Suche, Smarte Erinnerungen, Karte und Scrollen in der Zeitleiste sind bei großen Bibliotheken deutlich schneller. Allein die Gruppierung auf der Karte ist 2–3-mal schneller.',
        ),
        ChangeLogEntryStrings(
          title: 'Backups mit sichtbarem Fortschritt',
          description:
              'Der Sicherungsstatus zeigt jetzt den Fortschritt für jede Datei an, und große mehrteilige Uploads sind zuverlässiger.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Text in Fotos auswählen',
          description:
              'Die Bedienelemente bleiben während der Auswahl erreichbar, und durch Tippen auf ausgewählten Text wird die Auswahl aufgehoben.',
        ),
        ChangeLogEntryStrings(
          title: 'Ein aufgeräumteres Auswahlmenü',
          description:
              'Die Aktionen in der Auswahlleiste sind danach sortiert, wie oft du sie verwendest, und das Teilen-Symbol entspricht jetzt deiner Plattform.',
        ),
      ],
    ),
    'es': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Uso compartido de la biblioteca',
          description:
              'Comparte automáticamente tus álbumes actuales y futuros con tus familiares. Ve a Configuración → Familia, elige a un miembro y toca Compartir álbumes. Los álbumes nuevos se incluyen a medida que los creas.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Descripciones de álbumes',
          description:
              'Añade una descripción a un álbum junto con su nombre y foto de portada. Las descripciones se incluyen en tus enlaces compartidos, para que cualquiera que abra uno vea el contexto que añadiste.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Más rapidez en bibliotecas grandes',
          description:
              'La búsqueda, los Recuerdos inteligentes, el mapa y el desplazamiento por la cronología son mucho más rápidos si tienes una biblioteca grande. Solo la agrupación del mapa es entre 2 y 3 veces más rápida.',
        ),
        ChangeLogEntryStrings(
          title: 'Copias de seguridad que puedes seguir',
          description:
              'El Estado de la copia de seguridad ahora muestra el progreso de cada archivo, y las cargas grandes de varias partes son más fiables.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Seleccionar texto en fotos',
          description:
              'Los controles permanecen accesibles mientras seleccionas texto, y tocar el texto seleccionado borra la selección.',
        ),
        ChangeLogEntryStrings(
          title: 'Un menú de selección más ordenado',
          description:
              'Las acciones de la barra de selección se ordenan según la frecuencia con la que las usas, y el icono de compartir ahora coincide con el de tu plataforma.',
        ),
      ],
    ),
    'fr': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Partage de la photothèque',
          description:
              'Partagez automatiquement vos albums actuels et futurs avec les membres de votre famille. Accédez à Paramètres → Famille, choisissez un membre et touchez Partager les albums. Les nouveaux albums sont inclus dès leur création.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Descriptions d’albums',
          description:
              'Ajoutez une description à un album en plus de son nom et de sa photo de couverture. Les descriptions accompagnent vos liens partagés, afin que toute personne qui en ouvre un voie le contexte que vous avez ajouté.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Plus rapide avec les grandes photothèques',
          description:
              'La recherche, les Souvenirs intelligents, la carte et le défilement de la chronologie sont nettement plus rapides si votre photothèque est volumineuse. Le regroupement sur la carte est à lui seul 2 à 3 fois plus rapide.',
        ),
        ChangeLogEntryStrings(
          title: 'Des sauvegardes à suivre en direct',
          description:
              'L’état de la sauvegarde affiche désormais la progression de chaque fichier, et les envois volumineux en plusieurs parties sont plus fiables.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Sélection de texte dans les photos',
          description:
              'Les commandes restent accessibles pendant la sélection, et toucher le texte sélectionné efface la sélection.',
        ),
        ChangeLogEntryStrings(
          title: 'Un menu de sélection mieux ordonné',
          description:
              'Les actions de la barre de sélection sont classées selon leur fréquence d’utilisation, et l’icône de partage correspond désormais à votre plateforme.',
        ),
      ],
    ),
    'it': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Condivisione della libreria',
          description:
              'Condividi automaticamente gli album attuali e futuri con i membri della famiglia. Vai su Impostazioni → Famiglia, scegli un membro e tocca Condividi album. I nuovi album vengono inclusi man mano che li crei.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Descrizioni degli album',
          description:
              'Aggiungi a un album una descrizione oltre al nome e alla foto di copertina. Le descrizioni accompagnano i link condivisi, così chiunque ne apra uno vedrà il contesto che hai aggiunto.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Più veloce con le librerie grandi',
          description:
              'La ricerca, i Ricordi intelligenti, la mappa e lo scorrimento della sequenza temporale sono molto più veloci se hai una libreria grande. Il solo raggruppamento sulla mappa è da 2 a 3 volte più veloce.',
        ),
        ChangeLogEntryStrings(
          title: 'Backup da seguire in tempo reale',
          description:
              'Lo Stato backup ora mostra l’avanzamento di ogni file e i caricamenti multipart di grandi dimensioni sono più affidabili.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Selezione del testo nelle foto',
          description:
              'I controlli restano accessibili durante la selezione e toccando il testo selezionato la selezione viene annullata.',
        ),
        ChangeLogEntryStrings(
          title: 'Un menu di selezione più ordinato',
          description:
              'Le azioni nella barra di selezione sono ordinate in base alla frequenza con cui le usi e l’icona di condivisione ora corrisponde alla tua piattaforma.',
        ),
      ],
    ),
    'ja': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'ライブラリ共有',
          description:
              '現在および今後作成するアルバムを家族と自動的に共有できます。［設定］→［ファミリー］でメンバーを選び、［アルバムを共有］をタップしてください。新しいアルバムも作成時に自動で含まれます。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'アルバムの説明',
          description:
              'アルバムに名前やカバー写真とあわせて説明を追加できます。説明は共有リンクにも表示されるため、リンクを開いた人に追加した背景が伝わります。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '大規模ライブラリでも高速に',
          description:
              '大規模なライブラリで、検索、スマートメモリー、マップ、タイムラインのスクロールが大幅に高速化しました。マップのクラスタリングだけでも2～3倍高速です。',
        ),
        ChangeLogEntryStrings(
          title: '進捗が見えるバックアップ',
          description:
              'バックアップの状態にファイルごとの進捗が表示されるようになり、大容量のマルチパートアップロードの信頼性も向上しました。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '写真内のテキスト選択',
          description: 'テキストを選択中も操作ボタンにアクセスでき、選択したテキストをタップすると選択が解除されます。',
        ),
        ChangeLogEntryStrings(
          title: 'すっきりした選択メニュー',
          description: '選択バーの操作を使用頻度順に並べ替え、共有アイコンもお使いのプラットフォームに合うものになりました。',
        ),
      ],
    ),
    'nl': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Bibliotheek delen',
          description:
              'Deel je huidige en toekomstige albums automatisch met gezinsleden. Ga naar Instellingen → Familie, kies een lid en tik op Albums delen. Nieuwe albums worden toegevoegd zodra je ze maakt.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Albumbeschrijvingen',
          description:
              'Geef een album naast een naam en omslagfoto ook een beschrijving. Beschrijvingen gaan mee met je gedeelde links, zodat iedereen die een link opent de context ziet die je hebt toegevoegd.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Sneller bij grote bibliotheken',
          description:
              'Zoeken, Slimme herinneringen, de kaart en scrollen door de tijdlijn zijn allemaal aanzienlijk sneller als je een grote bibliotheek hebt. Alleen al het clusteren op de kaart is 2–3 keer sneller.',
        ),
        ChangeLogEntryStrings(
          title: 'Back-ups die je kunt volgen',
          description:
              'Back-up status toont nu de voortgang per bestand en grote meerdelige uploads zijn betrouwbaarder.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: "Tekst selecteren in foto's",
          description:
              'De bediening blijft bereikbaar terwijl je tekst selecteert en door op geselecteerde tekst te tikken wis je de selectie.',
        ),
        ChangeLogEntryStrings(
          title: 'Een overzichtelijker selectiemenu',
          description:
              'De acties in de selectiebalk zijn gerangschikt op hoe vaak je ze gebruikt en het deelpictogram past nu bij je platform.',
        ),
      ],
    ),
    'no': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Deling av bibliotek',
          description:
              'Del nåværende og fremtidige album automatisk med familiemedlemmer. Gå til Innstillinger → Familie, velg et medlem og trykk på Del album. Nye album tas med etter hvert som du oppretter dem.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Albumbeskrivelser',
          description:
              'Gi et album en beskrivelse i tillegg til navn og forsidebilde. Beskrivelsene følger de delte lenkene, slik at alle som åpner en, ser konteksten du la til.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Raskere med store biblioteker',
          description:
              'Søk, Smarte minner, kartet og rulling på tidslinjen er betydelig raskere hvis du har et stort bibliotek. Gruppering på kartet alene er 2–3 ganger raskere.',
        ),
        ChangeLogEntryStrings(
          title: 'Sikkerhetskopiering du kan følge',
          description:
              'Status for sikkerhetskopi viser nå fremdrift per fil, og store opplastinger i flere deler er mer pålitelige.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Velge tekst i bilder',
          description:
              'Kontrollene er fortsatt tilgjengelige mens du velger tekst, og et trykk på valgt tekst fjerner markeringen.',
        ),
        ChangeLogEntryStrings(
          title: 'En ryddigere valgmeny',
          description:
              'Handlingene i valglinjen er sortert etter hvor ofte du bruker dem, og deleikonet samsvarer nå med plattformen din.',
        ),
      ],
    ),
    'pl': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Udostępnianie biblioteki',
          description:
              'Automatycznie udostępniaj rodzinie swoje obecne i przyszłe albumy. Przejdź do Ustawienia → Rodzina, wybierz osobę i stuknij Udostępnij albumy. Nowe albumy będą dodawane w chwili ich utworzenia.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Opisy albumów',
          description:
              'Dodaj do albumu opis obok nazwy i zdjęcia na okładkę. Opisy są dołączane do udostępnionych linków, więc każda osoba, która otworzy link, zobaczy dodany przez Ciebie kontekst.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Szybciej przy dużych bibliotekach',
          description:
              'Wyszukiwanie, Inteligentne wspomnienia, mapa i przewijanie osi czasu działają znacznie szybciej, jeśli masz dużą bibliotekę. Samo grupowanie na mapie jest 2–3 razy szybsze.',
        ),
        ChangeLogEntryStrings(
          title: 'Kopie zapasowe z widocznym postępem',
          description:
              'Status kopii zapasowej pokazuje teraz postęp dla każdego pliku, a duże przesyłania wieloczęściowe są bardziej niezawodne.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Zaznaczanie tekstu na zdjęciach',
          description:
              'Elementy sterujące pozostają dostępne podczas zaznaczania, a stuknięcie zaznaczonego tekstu usuwa zaznaczenie.',
        ),
        ChangeLogEntryStrings(
          title: 'Uporządkowane menu zaznaczenia',
          description:
              'Działania na pasku zaznaczenia są uporządkowane według częstotliwości użycia, a ikona udostępniania jest teraz zgodna z Twoją platformą.',
        ),
      ],
    ),
    'pt_BR': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Compartilhamento da biblioteca',
          description:
              'Compartilhe automaticamente seus álbuns atuais e futuros com familiares. Acesse Opções → Família, escolha uma pessoa e toque em Compartilhar álbuns. Novos álbuns são incluídos conforme você os cria.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Descrições de álbuns',
          description:
              'Adicione uma descrição ao álbum, além do nome e da foto de capa. As descrições acompanham os links compartilhados, para que qualquer pessoa que abrir um deles veja o contexto que você adicionou.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Mais rapidez em bibliotecas grandes',
          description:
              'A pesquisa, as Memórias inteligentes, o mapa e a rolagem da linha do tempo ficaram muito mais rápidos para bibliotecas grandes. Só o agrupamento no mapa está de 2 a 3 vezes mais rápido.',
        ),
        ChangeLogEntryStrings(
          title: 'Backups que você pode acompanhar',
          description:
              'O Estado do backup agora mostra o progresso de cada arquivo, e uploads grandes em várias partes estão mais confiáveis.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Seleção de texto em fotos',
          description:
              'Os controles continuam acessíveis durante a seleção, e tocar no texto selecionado desfaz a seleção.',
        ),
        ChangeLogEntryStrings(
          title: 'Um menu de seleção mais organizado',
          description:
              'As ações na barra de seleção são ordenadas pela frequência de uso, e o ícone de compartilhamento agora corresponde à sua plataforma.',
        ),
      ],
    ),
    'pt_PT': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Partilha da biblioteca',
          description:
              'Partilhe automaticamente os seus álbuns atuais e futuros com familiares. Aceda a Definições → Família, escolha um membro e toque em Partilhar álbuns. Os novos álbuns são incluídos à medida que os cria.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Descrições de álbuns',
          description:
              'Adicione uma descrição a um álbum, além do nome e da fotografia de capa. As descrições acompanham as ligações partilhadas, para que qualquer pessoa que abra uma veja o contexto que adicionou.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Mais rápido com bibliotecas grandes',
          description:
              'A pesquisa, as Memórias inteligentes, o mapa e o deslocamento na cronologia são substancialmente mais rápidos se tiver uma biblioteca grande. Só o agrupamento no mapa é 2 a 3 vezes mais rápido.',
        ),
        ChangeLogEntryStrings(
          title: 'Cópias de segurança que pode acompanhar',
          description:
              'O Status da cópia de segurança mostra agora o progresso de cada ficheiro e os carregamentos multipartes grandes são mais fiáveis.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Selecionar texto em fotografias',
          description:
              'Os controlos continuam acessíveis durante a seleção e tocar no texto selecionado limpa a seleção.',
        ),
        ChangeLogEntryStrings(
          title: 'Um menu de seleção mais organizado',
          description:
              'As ações na barra de seleção são ordenadas pela frequência de utilização e o ícone de partilha corresponde agora à sua plataforma.',
        ),
      ],
    ),
    'ro': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Partajarea bibliotecii',
          description:
              'Partajează automat albumele actuale și viitoare cu membrii familiei. Accesează Setări → Familie, alege un membru și atinge Partajează albumele. Albumele noi sunt incluse pe măsură ce le creezi.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Descrieri pentru albume',
          description:
              'Adaugă unui album o descriere, pe lângă nume și fotografia de copertă. Descrierile însoțesc linkurile partajate, astfel încât oricine deschide unul vede contextul adăugat de tine.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Mai rapid pentru biblioteci mari',
          description:
              'Căutarea, Amintirile inteligente, harta și derularea cronologiei sunt mult mai rapide dacă ai o bibliotecă mare. Numai gruparea pe hartă este de 2–3 ori mai rapidă.',
        ),
        ChangeLogEntryStrings(
          title: 'Copii de siguranță pe care le poți urmări',
          description:
              'Stare copie de rezervă afișează acum progresul pentru fiecare fișier, iar încărcările multipart mari sunt mai fiabile.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Selectarea textului din fotografii',
          description:
              'Comenzile rămân accesibile în timpul selectării, iar atingerea textului selectat șterge selecția.',
        ),
        ChangeLogEntryStrings(
          title: 'Un meniu de selecție mai ordonat',
          description:
              'Acțiunile din bara de selecție sunt ordonate după frecvența utilizării, iar pictograma de partajare corespunde acum platformei tale.',
        ),
      ],
    ),
    'ru': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Общий доступ к библиотеке',
          description:
              'Автоматически делитесь текущими и будущими альбомами с членами семьи. Откройте Настройки → Семья, выберите участника и нажмите Поделиться альбомами. Новые альбомы будут добавляться по мере их создания.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Описания альбомов',
          description:
              'Добавляйте к альбому описание вместе с названием и фотографией обложки. Описания передаются по общим ссылкам, поэтому каждый, кто откроет ссылку, увидит добавленный вами контекст.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Быстрее для больших библиотек',
          description:
              'Поиск, Умные воспоминания, карта и прокрутка временной шкалы стали значительно быстрее для больших библиотек. Одна только группировка на карте работает в 2–3 раза быстрее.',
        ),
        ChangeLogEntryStrings(
          title: 'Резервное копирование с видимым прогрессом',
          description:
              'Статус резервного копирования теперь показывает прогресс для каждого файла, а большие многочастные загрузки стали надёжнее.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Выделение текста на фотографиях',
          description:
              'Элементы управления остаются доступными во время выделения, а нажатие на выделенный текст снимает выделение.',
        ),
        ChangeLogEntryStrings(
          title: 'Более аккуратное меню выбора',
          description:
              'Действия на панели выбора упорядочены по частоте использования, а значок «Поделиться» теперь соответствует вашей платформе.',
        ),
      ],
    ),
    'tr': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Kütüphane paylaşımı',
          description:
              'Mevcut ve gelecekteki albümlerinizi aile üyeleriyle otomatik olarak paylaşın. Ayarlar → Aile bölümüne gidin, bir üye seçin ve Albümleri paylaş seçeneğine dokunun. Yeni albümler oluşturuldukça otomatik olarak eklenir.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Albüm açıklamaları',
          description:
              'Bir albüme adı ve kapak fotoğrafının yanında bir açıklama ekleyin. Açıklamalar paylaşılan bağlantılarınızla birlikte gider; böylece bağlantıyı açan herkes eklediğiniz bağlamı görür.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Büyük kütüphanelerde daha hızlı',
          description:
              'Büyük bir kütüphaneniz varsa arama, Akıllı anılar, harita ve zaman çizelgesinde kaydırma çok daha hızlıdır. Yalnızca harita kümeleme bile 2–3 kat daha hızlıdır.',
        ),
        ChangeLogEntryStrings(
          title: 'Takip edebileceğiniz yedeklemeler',
          description:
              'Yedekleme durumu artık her dosyanın ilerlemesini gösteriyor ve büyük, çok parçalı yüklemeler daha güvenilir.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Fotoğraflarda metin seçme',
          description:
              'Metin seçerken kontroller erişilebilir kalır ve seçili metne dokunmak seçimi temizler.',
        ),
        ChangeLogEntryStrings(
          title: 'Daha düzenli bir seçim menüsü',
          description:
              'Seçim çubuğundaki işlemler kullanım sıklığına göre sıralanıyor ve paylaşım simgesi artık platformunuzla eşleşiyor.',
        ),
      ],
    ),
    'uk': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Спільний доступ до бібліотеки',
          description:
              'Автоматично діліться поточними й майбутніми альбомами з членами родини. Відкрийте Налаштування → Сім’я, виберіть учасника й натисніть Поділитися альбомами. Нові альбоми додаватимуться під час створення.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Описи альбомів',
          description:
              'Додавайте до альбому опис разом із назвою та фотографією обкладинки. Описи передаються за спільними посиланнями, тож кожен, хто відкриє посилання, побачить доданий вами контекст.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Швидше для великих бібліотек',
          description:
              'Пошук, Розумні спогади, карта й прокручування часової шкали стали значно швидшими для великих бібліотек. Саме групування на карті працює у 2–3 рази швидше.',
        ),
        ChangeLogEntryStrings(
          title: 'Резервне копіювання з видимим перебігом',
          description:
              'Стан резервного копіювання тепер показує перебіг для кожного файлу, а великі багатокомпонентні завантаження стали надійнішими.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Виділення тексту на фотографіях',
          description:
              'Елементи керування залишаються доступними під час виділення, а натискання на виділений текст скасовує виділення.',
        ),
        ChangeLogEntryStrings(
          title: 'Охайніше меню вибору',
          description:
              'Дії на панелі вибору впорядковано за частотою використання, а піктограма поширення тепер відповідає вашій платформі.',
        ),
      ],
    ),
    'vi': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Chia sẻ thư viện',
          description:
              'Tự động chia sẻ các album hiện tại và trong tương lai với thành viên gia đình. Vào Cài đặt → Gia đình, chọn một thành viên rồi nhấn Chia sẻ album. Album mới sẽ được thêm vào ngay khi bạn tạo.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Mô tả album',
          description:
              'Thêm mô tả cho album bên cạnh tên và ảnh bìa. Mô tả được hiển thị cùng liên kết chia sẻ, để bất kỳ ai mở liên kết đều thấy ngữ cảnh bạn đã thêm.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Nhanh hơn với thư viện lớn',
          description:
              'Tìm kiếm, Gợi nhớ kỷ niệm, bản đồ và cuộn dòng thời gian đều nhanh hơn đáng kể nếu bạn có thư viện lớn. Riêng việc nhóm trên bản đồ đã nhanh hơn 2–3 lần.',
        ),
        ChangeLogEntryStrings(
          title: 'Theo dõi tiến trình sao lưu',
          description:
              'Trạng thái sao lưu giờ hiển thị tiến trình của từng tệp, và các lượt tải lên nhiều phần dung lượng lớn đáng tin cậy hơn.',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: 'Chọn văn bản trong ảnh',
          description:
              'Các nút điều khiển vẫn trong tầm với khi bạn chọn văn bản, và nhấn vào văn bản đã chọn sẽ xóa lựa chọn.',
        ),
        ChangeLogEntryStrings(
          title: 'Menu lựa chọn gọn gàng hơn',
          description:
              'Các thao tác trên thanh lựa chọn được sắp xếp theo tần suất bạn sử dụng, và biểu tượng chia sẻ giờ phù hợp với nền tảng của bạn.',
        ),
      ],
    ),
    'zh_CN': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: '图库共享',
          description:
              '自动与家人共享你当前和今后创建的相册。前往“设置”→“家庭”，选择一位成员，然后轻点“共享相册”。新建相册会在创建时自动包含在内。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '相册描述',
          description:
              '除了名称和封面照片外，现在还可以为相册添加描述。描述会随共享链接一起显示，让打开链接的任何人都能看到你添加的背景信息。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '大型图库更流畅',
          description: '如果你的图库规模较大，搜索、智能回忆、地图和时间线滚动现在都会快得多。仅地图聚类速度就提升了 2–3 倍。',
        ),
        ChangeLogEntryStrings(
          title: '看得见进度的备份',
          description: '“备份状态”现在会显示每个文件的进度，大型分片上传也更加可靠。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '选择照片中的文字',
          description: '选择文字时，控件会始终保持可用；轻点已选文字即可清除选择。',
        ),
        ChangeLogEntryStrings(
          title: '更整洁的选择菜单',
          description: '选择栏中的操作会按使用频率排序，共享图标现在也会与所用平台保持一致。',
        ),
      ],
    ),
    'zh_TW': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: '圖庫共享',
          description:
              '自動與家人共享您目前和未來建立的相簿。前往「設定」→「家庭」，選擇一位成員，然後點一下「共享相簿」。新相簿會在建立時自動包含在內。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '相簿描述',
          description:
              '除了名稱和封面照片外，現在還可以為相簿新增描述。描述會隨共享連結一併顯示，讓開啟連結的任何人都能看到您新增的背景資訊。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '大型圖庫更流暢',
          description: '如果您的圖庫較大，搜尋、自動分類回憶、地圖和時間軸捲動現在都快得多。僅地圖分群速度就提升了 2–3 倍。',
        ),
        ChangeLogEntryStrings(
          title: '看得見進度的備份',
          description: '「備份狀態」現在會顯示每個檔案的進度，大型分段上傳也更加可靠。',
          isOnlineOnly: true,
        ),
        ChangeLogEntryStrings(
          title: '選取照片中的文字',
          description: '選取文字時，控制項會保持可用；點一下已選取的文字即可清除選取。',
        ),
        ChangeLogEntryStrings(
          title: '更整潔的選取選單',
          description: '選取列中的操作會按使用頻率排序，共享圖示現在也會與您使用的平台一致。',
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

  const ChangeLogEntryStrings({
    required this.title,
    required this.description,
    this.isOnlineOnly = false,
    this.isLocalGalleryOnly = false,
  }) : assert(!(isOnlineOnly && isLocalGalleryOnly));
}

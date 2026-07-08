import 'dart:ui';

class ChangeLogStrings {
  final String title1;
  final String desc1;
  final String desc1Item1;
  final String desc1Item2;
  final String title2;
  final String desc2;
  final String title3;
  final String desc3;
  final String title4;
  final String desc4;

  const ChangeLogStrings({
    required this.title1,
    required this.desc1,
    this.desc1Item1 = '',
    this.desc1Item2 = '',
    this.title2 = '',
    this.desc2 = '',
    this.title3 = '',
    this.desc3 = '',
    this.title4 = '',
    this.desc4 = '',
  });

  bool get hasVisibleEntries =>
      title1.trim().isNotEmpty ||
      desc1.trim().isNotEmpty ||
      desc1Item1.trim().isNotEmpty ||
      desc1Item2.trim().isNotEmpty ||
      title2.trim().isNotEmpty ||
      desc2.trim().isNotEmpty ||
      title3.trim().isNotEmpty ||
      desc3.trim().isNotEmpty ||
      title4.trim().isNotEmpty ||
      desc4.trim().isNotEmpty;

  static ChangeLogStrings? maybeForLocale(
    Locale locale, {
    bool isLocalGallery = false,
  }) {
    final key = locale.countryCode != null && locale.countryCode!.isNotEmpty
        ? '${locale.languageCode}_${locale.countryCode}'
        : locale.languageCode;
    final translations = isLocalGallery ? _offlineTranslations : _translations;
    final strings =
        translations[key] ??
        translations[locale.languageCode] ??
        translations['en'];

    if (strings == null || !strings.hasVisibleEntries) {
      return null;
    }
    return strings;
  }

  static bool hasContentForLocale(
    Locale locale, {
    bool isLocalGallery = false,
  }) {
    return maybeForLocale(locale, isLocalGallery: isLocalGallery) != null;
  }

  static const Map<String, ChangeLogStrings> _translations = {
    'en': ChangeLogStrings(
      title1: 'A fresh new look',
      desc1:
          "We've given the app a fresh look, with new fonts, colors, spacing, and buttons throughout. Plus, feed gets its own tab in the bottom navigation.",
      title2: 'Albums, all in one place',
      desc2:
          'All your albums (backed up, shared, and on-device) now live on a single page. Search, switch between grid and list view, and order them based on your preferences.',
      title3: 'A bunch of improvements',
      desc3:
          "Photos download much faster, face thumbnail generation is quicker, and the text recognition animation feels smoother. You can also now bulk ignore faces straight from a photo's info panel. Plus a whole lot of squashed bugs.",
    ),
    'cs': ChangeLogStrings(
      title1: 'Zcela nový vzhled',
      desc1:
          'Dali jsme aplikaci svěží vzhled s novými fonty, barvami, rozestupy a tlačítky napříč celou aplikací. Feed má navíc vlastní kartu ve spodní navigaci.',
      title2: 'Alba, všechna na jednom místě',
      desc2:
          'Všechna vaše alba (zálohovaná, sdílená i v zařízení) teď najdete na jedné stránce. Můžete vyhledávat, přepínat mezi mřížkou a seznamem a řadit je podle svých preferencí.',
      title3: 'Spousta vylepšení',
      desc3:
          'Fotky se stahují mnohem rychleji, generování miniatur obličejů je rychlejší a animace rozpoznávání textu je plynulejší. Nově také můžete hromadně ignorovat obličeje přímo z informačního panelu fotky. A opravili jsme spoustu chyb.',
    ),
    'de': ChangeLogStrings(
      title1: 'Ein frischer neuer Look',
      desc1:
          'Wir haben der App einen frischen Look gegeben, mit neuen Schriften, Farben, Abständen und Buttons überall. Außerdem bekommt der Feed einen eigenen Tab in der unteren Navigation.',
      title2: 'Alben, alle an einem Ort',
      desc2:
          'Alle deine Alben (gesichert, geteilt und auf dem Gerät) befinden sich jetzt auf einer einzigen Seite. Suche, wechsle zwischen Raster- und Listenansicht und sortiere sie nach deinen Vorlieben.',
      title3: 'Viele Verbesserungen',
      desc3:
          'Fotos werden viel schneller heruntergeladen, Gesichtsvorschaubilder werden schneller erstellt und die Texterkennungsanimation wirkt flüssiger. Du kannst jetzt außerdem Gesichter direkt im Infobereich eines Fotos gesammelt ignorieren. Dazu kommen viele behobene Fehler.',
    ),
    'es': ChangeLogStrings(
      title1: 'Un nuevo aspecto renovado',
      desc1:
          'Le hemos dado a la app un aspecto renovado, con nuevas fuentes, colores, espaciado y botones en toda la aplicación. Además, el feed ahora tiene su propia pestaña en la navegación inferior.',
      title2: 'Álbumes, todos en un solo lugar',
      desc2:
          'Todos tus álbumes (respaldados, compartidos y del dispositivo) ahora viven en una sola página. Busca, cambia entre vista de cuadrícula y lista, y ordénalos según tus preferencias.',
      title3: 'Un montón de mejoras',
      desc3:
          'Las fotos se descargan mucho más rápido, la generación de miniaturas de rostros es más veloz y la animación de reconocimiento de texto se siente más fluida. También puedes ignorar rostros en bloque directamente desde el panel de información de una foto. Además de muchos errores corregidos.',
    ),
    'fr': ChangeLogStrings(
      title1: 'Un tout nouveau style',
      desc1:
          "Nous avons donné un nouveau souffle à l'app, avec de nouvelles polices, couleurs, espacements et de nouveaux boutons partout. Le fil dispose aussi de son propre onglet dans la navigation du bas.",
      title2: 'Tous vos albums au même endroit',
      desc2:
          'Tous vos albums (sauvegardés, partagés et présents sur l’appareil) sont maintenant réunis sur une seule page. Recherchez, passez de la grille à la liste, et triez-les selon vos préférences.',
      title3: 'De nombreuses améliorations',
      desc3:
          "Les photos se téléchargent beaucoup plus vite, la génération des vignettes de visages est plus rapide et l'animation de reconnaissance de texte est plus fluide. Vous pouvez aussi ignorer plusieurs visages à la fois directement depuis le panneau d'informations d'une photo. Sans oublier de nombreux bugs corrigés.",
    ),
    'it': ChangeLogStrings(
      title1: 'Un nuovo look fresco',
      desc1:
          "Abbiamo dato all'app un look più fresco, con nuovi font, colori, spaziature e pulsanti in tutta l'esperienza. Inoltre, il feed ha una scheda dedicata nella navigazione inferiore.",
      title2: 'Album, tutti in un unico posto',
      desc2:
          'Tutti i tuoi album (sottoposti a backup, condivisi e sul dispositivo) ora si trovano in un’unica pagina. Cerca, passa dalla vista griglia alla lista e ordinali in base alle tue preferenze.',
      title3: 'Tanti miglioramenti',
      desc3:
          'Le foto si scaricano molto più velocemente, la generazione delle miniature dei volti è più rapida e l’animazione del riconoscimento del testo è più fluida. Ora puoi anche ignorare più volti in blocco direttamente dal pannello informazioni di una foto. E abbiamo risolto molti bug.',
    ),
    'ja': ChangeLogStrings(
      title1: '新しくなった見た目',
      desc1:
          'アプリ全体のフォント、色、余白、ボタンを見直し、より新鮮な見た目にしました。さらに、フィードが下部ナビゲーションの専用タブになりました。',
      title2: 'すべてのアルバムを一か所に',
      desc2:
          'バックアップ済み、共有中、端末上のすべてのアルバムが1つのページにまとまりました。検索、グリッド表示とリスト表示の切り替え、好みに合わせた並べ替えができます。',
      title3: 'たくさんの改善',
      desc3:
          '写真のダウンロードが大幅に速くなり、顔サムネイルの生成も高速化され、テキスト認識のアニメーションもよりスムーズになりました。写真の情報パネルから複数の顔をまとめて無視できるようにもなりました。その他、多くのバグも修正しています。',
    ),
    'nl': ChangeLogStrings(
      title1: 'Een frisse nieuwe look',
      desc1:
          'We hebben de app een frisse look gegeven, met nieuwe lettertypen, kleuren, ruimte en knoppen overal. Bovendien heeft de feed nu een eigen tab in de navigatie onderaan.',
      title2: 'Albums, allemaal op één plek',
      desc2:
          'Al je albums (geback-upt, gedeeld en op je apparaat) staan nu op één pagina. Zoek, wissel tussen raster- en lijstweergave en sorteer ze zoals jij wilt.',
      title3: 'Een heleboel verbeteringen',
      desc3:
          'Foto’s downloaden veel sneller, gezichtminiaturen worden sneller gegenereerd en de animatie voor tekstherkenning voelt vloeiender. Je kunt nu ook meerdere gezichten tegelijk negeren vanuit het infopaneel van een foto. En we hebben heel wat bugs opgelost.',
    ),
    'no': ChangeLogStrings(
      title1: 'Et friskt nytt utseende',
      desc1:
          'Vi har gitt appen et friskt utseende, med nye skrifter, farger, avstand og knapper overalt. I tillegg får feeden sin egen fane i bunnavigasjonen.',
      title2: 'Album, samlet på ett sted',
      desc2:
          'Alle albumene dine (sikkerhetskopierte, delte og på enheten) finnes nå på én side. Søk, bytt mellom rutenett- og listevisning, og sorter dem slik du foretrekker.',
      title3: 'Mange forbedringer',
      desc3:
          'Bilder lastes ned mye raskere, generering av ansiktsminiatyrer går raskere, og animasjonen for tekstgjenkjenning føles jevnere. Du kan også ignorere flere ansikter samtidig direkte fra infopanelet til et bilde. I tillegg har vi fikset en hel del feil.',
    ),
    'pl': ChangeLogStrings(
      title1: 'Świeży, nowy wygląd',
      desc1:
          'Odświeżyliśmy wygląd aplikacji, wprowadzając nowe fonty, kolory, odstępy i przyciski w całej aplikacji. Dodatkowo feed ma teraz własną kartę w dolnej nawigacji.',
      title2: 'Albumy w jednym miejscu',
      desc2:
          'Wszystkie Twoje albumy (z kopią zapasową, udostępnione i z urządzenia) znajdują się teraz na jednej stronie. Możesz je wyszukiwać, przełączać widok siatki i listy oraz sortować według własnych preferencji.',
      title3: 'Mnóstwo usprawnień',
      desc3:
          'Zdjęcia pobierają się znacznie szybciej, miniatury twarzy generują się szybciej, a animacja rozpoznawania tekstu jest płynniejsza. Możesz też zbiorczo ignorować twarze bezpośrednio z panelu informacji o zdjęciu. Do tego naprawiliśmy wiele błędów.',
    ),
    'pt_BR': ChangeLogStrings(
      title1: 'Um visual renovado',
      desc1:
          'Demos ao app um visual renovado, com novas fontes, cores, espaçamentos e botões por toda parte. Além disso, o feed agora tem sua própria aba na navegação inferior.',
      title2: 'Álbuns, todos em um só lugar',
      desc2:
          'Todos os seus álbuns (com backup, compartilhados e no dispositivo) agora ficam em uma única página. Pesquise, alterne entre visualização em grade e lista, e ordene tudo conforme suas preferências.',
      title3: 'Várias melhorias',
      desc3:
          'As fotos baixam muito mais rápido, a geração de miniaturas de rostos ficou mais ágil e a animação de reconhecimento de texto está mais suave. Agora você também pode ignorar rostos em massa diretamente pelo painel de informações de uma foto. E corrigimos muitos bugs.',
    ),
    'pt_PT': ChangeLogStrings(
      title1: 'Um novo visual renovado',
      desc1:
          'Demos à app um visual renovado, com novas fontes, cores, espaçamentos e botões em toda a experiência. Além disso, o feed passa a ter o seu próprio separador na navegação inferior.',
      title2: 'Álbuns, todos num só lugar',
      desc2:
          'Todos os seus álbuns (com cópia de segurança, partilhados e no dispositivo) estão agora numa única página. Pesquise, alterne entre grelha e lista, e ordene-os de acordo com as suas preferências.',
      title3: 'Muitas melhorias',
      desc3:
          'As fotografias são descarregadas muito mais depressa, a geração de miniaturas de rostos é mais rápida e a animação de reconhecimento de texto está mais suave. Agora também pode ignorar rostos em massa diretamente a partir do painel de informações de uma fotografia. E corrigimos muitos bugs.',
    ),
    'ro': ChangeLogStrings(
      title1: 'Un aspect nou și proaspăt',
      desc1:
          'Am oferit aplicației un aspect nou, cu fonturi, culori, spațieri și butoane noi peste tot. În plus, feedul are acum propria filă în navigarea de jos.',
      title2: 'Albume, toate într-un singur loc',
      desc2:
          'Toate albumele tale (cu backup, partajate și de pe dispozitiv) se află acum pe o singură pagină. Caută, comută între vizualizarea grilă și listă și sortează-le după preferințe.',
      title3: 'O mulțime de îmbunătățiri',
      desc3:
          'Fotografiile se descarcă mult mai rapid, generarea miniaturilor pentru fețe este mai rapidă, iar animația de recunoaștere a textului este mai fluidă. Acum poți ignora în bloc fețe direct din panoul de informații al unei fotografii. Plus multe buguri remediate.',
    ),
    'ru': ChangeLogStrings(
      title1: 'Свежий новый вид',
      desc1:
          'Мы обновили внешний вид приложения: новые шрифты, цвета, отступы и кнопки по всему интерфейсу. Кроме того, лента получила отдельную вкладку в нижней навигации.',
      title2: 'Все альбомы в одном месте',
      desc2:
          'Все ваши альбомы (с резервной копией, общие и на устройстве) теперь находятся на одной странице. Ищите, переключайтесь между сеткой и списком и сортируйте их как вам удобно.',
      title3: 'Много улучшений',
      desc3:
          'Фотографии скачиваются гораздо быстрее, миниатюры лиц создаются быстрее, а анимация распознавания текста стала плавнее. Теперь также можно массово игнорировать лица прямо из панели информации о фотографии. И, конечно, мы исправили множество ошибок.',
    ),
    'tr': ChangeLogStrings(
      title1: 'Yepyeni ve ferah bir görünüm',
      desc1:
          'Uygulamaya baştan sona yeni yazı tipleri, renkler, boşluklar ve düğmelerle ferah bir görünüm kazandırdık. Ayrıca akış artık alt gezinti çubuğunda kendi sekmesine sahip.',
      title2: 'Albümler, hepsi tek yerde',
      desc2:
          'Tüm albümleriniz (yedeklenen, paylaşılan ve cihazdaki) artık tek bir sayfada. Arama yapabilir, ızgara ve liste görünümü arasında geçiş yapabilir ve tercihlerinize göre sıralayabilirsiniz.',
      title3: 'Bir sürü iyileştirme',
      desc3:
          'Fotoğraflar çok daha hızlı indiriliyor, yüz küçük resimleri daha hızlı oluşturuluyor ve metin tanıma animasyonu daha akıcı hissettiriyor. Ayrıca artık bir fotoğrafın bilgi panelinden yüzleri toplu olarak yok sayabilirsiniz. Birçok hata da giderildi.',
    ),
    'uk': ChangeLogStrings(
      title1: 'Свіжий новий вигляд',
      desc1:
          'Ми оновили вигляд застосунку: нові шрифти, кольори, відступи й кнопки по всьому інтерфейсу. Крім того, стрічка отримала власну вкладку в нижній навігації.',
      title2: 'Усі альбоми в одному місці',
      desc2:
          'Усі ваші альбоми (з резервною копією, спільні та на пристрої) тепер на одній сторінці. Шукайте, перемикайтеся між сіткою та списком і впорядковуйте їх за власними вподобаннями.',
      title3: 'Багато покращень',
      desc3:
          'Фотографії завантажуються значно швидше, мініатюри облич створюються швидше, а анімація розпізнавання тексту стала плавнішою. Тепер також можна масово ігнорувати обличчя прямо з панелі інформації про фото. І ми виправили багато помилок.',
    ),
    'vi': ChangeLogStrings(
      title1: 'Diện mạo mới mẻ',
      desc1:
          'Chúng tôi đã làm mới giao diện ứng dụng với phông chữ, màu sắc, khoảng cách và nút mới trên toàn bộ ứng dụng. Ngoài ra, bảng tin giờ có tab riêng ở thanh điều hướng dưới cùng.',
      title2: 'Tất cả album ở một nơi',
      desc2:
          'Tất cả album của bạn (đã sao lưu, được chia sẻ và trên thiết bị) giờ nằm trên một trang duy nhất. Tìm kiếm, chuyển giữa chế độ lưới và danh sách, rồi sắp xếp theo ý bạn.',
      title3: 'Rất nhiều cải tiến',
      desc3:
          'Ảnh tải xuống nhanh hơn nhiều, việc tạo ảnh thu nhỏ khuôn mặt nhanh hơn và hoạt ảnh nhận dạng văn bản mượt hơn. Giờ bạn cũng có thể bỏ qua hàng loạt khuôn mặt ngay từ bảng thông tin của ảnh. Cùng với rất nhiều lỗi đã được sửa.',
    ),
    'zh_CN': ChangeLogStrings(
      title1: '焕然一新的外观',
      desc1: '我们为应用带来了全新的外观，整体更新了字体、颜色、间距和按钮。另外，动态现在在底部导航中拥有自己的标签页。',
      title2: '所有相册，集中一处',
      desc2: '你的所有相册（已备份、已共享和设备上的相册）现在都集中在一个页面。你可以搜索、在网格和列表视图之间切换，并按自己的偏好排序。',
      title3: '一系列改进',
      desc3:
          '照片下载速度大幅提升，人脸缩略图生成更快，文字识别动画也更流畅。现在你还可以直接从照片信息面板批量忽略人脸。此外，我们还修复了大量问题。',
    ),
  };

  static const Map<String, ChangeLogStrings> _offlineTranslations = {
    'en': ChangeLogStrings(
      title1: 'A fresh new look',
      desc1:
          "We've given the app a fresh look, with new fonts, colors, spacing, and buttons throughout. Albums has also been redesigned for easier browsing.",
    ),
    'cs': ChangeLogStrings(
      title1: 'Zcela nový vzhled',
      desc1:
          'Dali jsme aplikaci svěží vzhled s novými fonty, barvami, rozestupy a tlačítky napříč celou aplikací. Alba jsme také přepracovali pro snazší procházení.',
    ),
    'de': ChangeLogStrings(
      title1: 'Ein frischer neuer Look',
      desc1:
          'Wir haben der App einen frischen Look gegeben, mit neuen Schriften, Farben, Abständen und Buttons überall. Alben wurden außerdem für einfacheres Stöbern neu gestaltet.',
    ),
    'es': ChangeLogStrings(
      title1: 'Un nuevo aspecto renovado',
      desc1:
          'Le hemos dado a la app un aspecto renovado, con nuevas fuentes, colores, espaciado y botones en toda la aplicación. Álbumes también se ha rediseñado para que sea más fácil explorarlos.',
    ),
    'fr': ChangeLogStrings(
      title1: 'Un tout nouveau style',
      desc1:
          "Nous avons donné un nouveau souffle à l'app, avec de nouvelles polices, couleurs, espacements et de nouveaux boutons partout. Les albums ont aussi été repensés pour une navigation plus simple.",
    ),
    'it': ChangeLogStrings(
      title1: 'Un nuovo look fresco',
      desc1:
          "Abbiamo dato all'app un look più fresco, con nuovi font, colori, spaziature e pulsanti in tutta l'esperienza. Anche Album è stato ridisegnato per una navigazione più semplice.",
    ),
    'ja': ChangeLogStrings(
      title1: '新しくなった見た目',
      desc1:
          'アプリ全体のフォント、色、余白、ボタンを見直し、より新鮮な見た目にしました。アルバムもより見つけやすく閲覧しやすいように再設計しました。',
    ),
    'nl': ChangeLogStrings(
      title1: 'Een frisse nieuwe look',
      desc1:
          'We hebben de app een frisse look gegeven, met nieuwe lettertypen, kleuren, ruimte en knoppen overal. Albums is ook opnieuw ontworpen zodat je er makkelijker doorheen bladert.',
    ),
    'no': ChangeLogStrings(
      title1: 'Et friskt nytt utseende',
      desc1:
          'Vi har gitt appen et friskt utseende, med nye skrifter, farger, avstand og knapper overalt. Album er også redesignet for enklere blaing.',
    ),
    'pl': ChangeLogStrings(
      title1: 'Świeży, nowy wygląd',
      desc1:
          'Odświeżyliśmy wygląd aplikacji, wprowadzając nowe fonty, kolory, odstępy i przyciski w całej aplikacji. Albumy zostały też przeprojektowane, aby łatwiej było je przeglądać.',
    ),
    'pt_BR': ChangeLogStrings(
      title1: 'Um visual renovado',
      desc1:
          'Demos ao app um visual renovado, com novas fontes, cores, espaçamentos e botões por toda parte. Álbuns também foi redesenhado para facilitar a navegação.',
    ),
    'pt_PT': ChangeLogStrings(
      title1: 'Um novo visual renovado',
      desc1:
          'Demos à app um visual renovado, com novas fontes, cores, espaçamentos e botões em toda a experiência. Os álbuns também foram redesenhados para facilitar a navegação.',
    ),
    'ro': ChangeLogStrings(
      title1: 'Un aspect nou și proaspăt',
      desc1:
          'Am oferit aplicației un aspect nou, cu fonturi, culori, spațieri și butoane noi peste tot. Albumele au fost și ele redesenate pentru o navigare mai ușoară.',
    ),
    'ru': ChangeLogStrings(
      title1: 'Свежий новый вид',
      desc1:
          'Мы обновили внешний вид приложения: новые шрифты, цвета, отступы и кнопки по всему интерфейсу. Альбомы тоже были переработаны, чтобы их было удобнее просматривать.',
    ),
    'tr': ChangeLogStrings(
      title1: 'Yepyeni ve ferah bir görünüm',
      desc1:
          'Uygulamaya baştan sona yeni yazı tipleri, renkler, boşluklar ve düğmelerle ferah bir görünüm kazandırdık. Albümler de daha kolay gezinme için yeniden tasarlandı.',
    ),
    'uk': ChangeLogStrings(
      title1: 'Свіжий новий вигляд',
      desc1:
          'Ми оновили вигляд застосунку: нові шрифти, кольори, відступи й кнопки по всьому інтерфейсу. Альбоми також перероблено для зручнішого перегляду.',
    ),
    'vi': ChangeLogStrings(
      title1: 'Diện mạo mới mẻ',
      desc1:
          'Chúng tôi đã làm mới giao diện ứng dụng với phông chữ, màu sắc, khoảng cách và nút mới trên toàn bộ ứng dụng. Album cũng được thiết kế lại để duyệt dễ hơn.',
    ),
    'zh_CN': ChangeLogStrings(
      title1: '焕然一新的外观',
      desc1: '我们为应用带来了全新的外观，整体更新了字体、颜色、间距和按钮。相册也经过重新设计，浏览起来更轻松。',
    ),
  };
}

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
    required bool isAndroid,
  }) {
    final key = locale.countryCode != null && locale.countryCode!.isNotEmpty
        ? '${locale.languageCode}_${locale.countryCode}'
        : locale.languageCode;
    final strings =
        _featureTranslations[key] ??
        _featureTranslations[locale.languageCode] ??
        _featureTranslations['en'];

    if (strings == null) {
      return null;
    }

    final changeLog = _forFeatureStrings(
      strings,
      isLocalGallery: isLocalGallery,
      isAndroid: isAndroid,
    );
    if (!changeLog.hasVisibleEntries) {
      return null;
    }
    return changeLog;
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

  static ChangeLogStrings _forFeatureStrings(
    _ChangeLogFeatureStrings strings, {
    required bool isLocalGallery,
    required bool isAndroid,
  }) {
    if (isLocalGallery) {
      return isAndroid
          ? ChangeLogStrings(
              title1: strings.deleteTitle,
              desc1: strings.localAndroidDeleteDesc,
              title2: strings.storageTitle,
              desc2: strings.storageDesc,
            )
          : ChangeLogStrings(
              title1: strings.storageTitle,
              desc1: strings.storageDesc,
            );
    }

    return isAndroid
        ? ChangeLogStrings(
            title1: strings.deleteTitle,
            desc1: strings.onlineAndroidDeleteDesc,
            title2: strings.castTitle,
            desc2: strings.castDesc,
            title3: strings.storageTitle,
            desc3: strings.storageDesc,
          )
        : ChangeLogStrings(
            title1: strings.castTitle,
            desc1: strings.castDesc,
            title2: strings.storageTitle,
            desc2: strings.storageDesc,
          );
  }

  static const Map<String, _ChangeLogFeatureStrings> _featureTranslations = {
    'en': _ChangeLogFeatureStrings(
      deleteTitle: 'Easier delete confirmations',
      onlineAndroidDeleteDesc:
          'When deleting from your device, Ente can help you set up media management to avoid repeated system prompts. Ente can also remember your last delete choice.',
      localAndroidDeleteDesc:
          'When deleting from your device, Ente can help you set up media management to avoid repeated system prompts.',
      castTitle: 'Cast to multiple screens',
      castDesc:
          "You can now cast albums to more than one screen at a time, view active sessions, and stop a specific session when you're done.",
      storageTitle: 'More reliable storage cleanup',
      storageDesc:
          'Ente now clears temporary image and video files more reliably, keeping the app from holding on to extra device storage.',
    ),
    'cs': _ChangeLogFeatureStrings(
      deleteTitle: 'Snazší potvrzení odstranění',
      onlineAndroidDeleteDesc:
          'Při odstraňování ze zařízení vám Ente může pomoci nastavit správu médií, abyste se vyhnuli opakovaným systémovým výzvám. Ente si také může zapamatovat vaši poslední volbu odstranění.',
      localAndroidDeleteDesc:
          'Při odstraňování ze zařízení vám Ente může pomoci nastavit správu médií, abyste se vyhnuli opakovaným systémovým výzvám.',
      castTitle: 'Promítání na více obrazovek',
      castDesc:
          'Alba teď můžete promítat na více obrazovek najednou, zobrazit aktivní relace a po skončení zastavit konkrétní relaci.',
      storageTitle: 'Spolehlivější čištění úložiště',
      storageDesc:
          'Ente teď spolehlivěji odstraňuje dočasné soubory obrázků a videí, takže aplikace nezabírá zbytečně další místo v úložišti zařízení.',
    ),
    'de': _ChangeLogFeatureStrings(
      deleteTitle: 'Einfachere Löschbestätigungen',
      onlineAndroidDeleteDesc:
          'Beim Löschen von deinem Gerät kann Ente dir helfen, die Medienverwaltung einzurichten, um wiederholte Systemabfragen zu vermeiden. Ente kann sich auch deine letzte Löschentscheidung merken.',
      localAndroidDeleteDesc:
          'Beim Löschen von deinem Gerät kann Ente dir helfen, die Medienverwaltung einzurichten, um wiederholte Systemabfragen zu vermeiden.',
      castTitle: 'Auf mehrere Bildschirme streamen',
      castDesc:
          'Du kannst Alben jetzt auf mehr als einen Bildschirm gleichzeitig streamen, aktive Sitzungen anzeigen und eine bestimmte Sitzung beenden, wenn du fertig bist.',
      storageTitle: 'Zuverlässigere Speicherbereinigung',
      storageDesc:
          'Ente entfernt temporäre Bild- und Videodateien jetzt zuverlässiger, damit die App keinen zusätzlichen Gerätespeicher belegt.',
    ),
    'es': _ChangeLogFeatureStrings(
      deleteTitle: 'Confirmaciones de eliminación más sencillas',
      onlineAndroidDeleteDesc:
          'Al eliminar desde tu dispositivo, Ente puede ayudarte a configurar la gestión de medios para evitar solicitudes repetidas del sistema. Ente también puede recordar tu última elección de eliminación.',
      localAndroidDeleteDesc:
          'Al eliminar desde tu dispositivo, Ente puede ayudarte a configurar la gestión de medios para evitar solicitudes repetidas del sistema.',
      castTitle: 'Transmitir a varias pantallas',
      castDesc:
          'Ahora puedes transmitir álbumes a más de una pantalla a la vez, ver las sesiones activas y detener una sesión específica cuando termines.',
      storageTitle: 'Limpieza de almacenamiento más fiable',
      storageDesc:
          'Ente ahora elimina los archivos temporales de imágenes y videos con mayor fiabilidad, evitando que la app retenga almacenamiento adicional del dispositivo.',
    ),
    'fr': _ChangeLogFeatureStrings(
      deleteTitle: 'Confirmations de suppression plus simples',
      onlineAndroidDeleteDesc:
          'Lorsque vous supprimez des éléments de votre appareil, Ente peut vous aider à configurer la gestion des médias afin d’éviter les invites système répétées. Ente peut aussi mémoriser votre dernier choix de suppression.',
      localAndroidDeleteDesc:
          'Lorsque vous supprimez des éléments de votre appareil, Ente peut vous aider à configurer la gestion des médias afin d’éviter les invites système répétées.',
      castTitle: 'Diffuser sur plusieurs écrans',
      castDesc:
          'Vous pouvez maintenant diffuser des albums sur plusieurs écrans à la fois, voir les sessions actives et arrêter une session précise lorsque vous avez terminé.',
      storageTitle: 'Nettoyage du stockage plus fiable',
      storageDesc:
          'Ente supprime désormais les fichiers temporaires d’images et de vidéos de manière plus fiable, afin que l’app n’occupe pas inutilement de l’espace sur votre appareil.',
    ),
    'it': _ChangeLogFeatureStrings(
      deleteTitle: 'Conferme di eliminazione più semplici',
      onlineAndroidDeleteDesc:
          'Quando elimini dal dispositivo, Ente può aiutarti a configurare la gestione dei contenuti multimediali per evitare richieste di sistema ripetute. Ente può anche ricordare la tua ultima scelta di eliminazione.',
      localAndroidDeleteDesc:
          'Quando elimini dal dispositivo, Ente può aiutarti a configurare la gestione dei contenuti multimediali per evitare richieste di sistema ripetute.',
      castTitle: 'Trasmetti su più schermi',
      castDesc:
          'Ora puoi trasmettere gli album su più di uno schermo alla volta, vedere le sessioni attive e interrompere una sessione specifica quando hai finito.',
      storageTitle: 'Pulizia dello spazio più affidabile',
      storageDesc:
          "Ente ora elimina i file temporanei di immagini e video in modo più affidabile, evitando che l'app trattenga spazio extra sul dispositivo.",
    ),
    'ja': _ChangeLogFeatureStrings(
      deleteTitle: '削除確認がより簡単に',
      onlineAndroidDeleteDesc:
          'デバイスから削除するとき、Ente はメディア管理の設定を案内し、繰り返し表示されるシステム確認を避けられるようにします。Ente は最後に選んだ削除方法を記憶することもできます。',
      localAndroidDeleteDesc:
          'デバイスから削除するとき、Ente はメディア管理の設定を案内し、繰り返し表示されるシステム確認を避けられるようにします。',
      castTitle: '複数の画面にキャスト',
      castDesc:
          'アルバムを複数の画面に同時にキャストし、アクティブなセッションを確認して、終了したい特定のセッションだけを停止できるようになりました。',
      storageTitle: 'ストレージクリーンアップの信頼性向上',
      storageDesc:
          'Ente は一時的な画像ファイルと動画ファイルをより確実に削除し、アプリが余分なデバイスストレージを使い続けないようにします。',
    ),
    'nl': _ChangeLogFeatureStrings(
      deleteTitle: 'Eenvoudigere verwijderbevestigingen',
      onlineAndroidDeleteDesc:
          'Wanneer je iets van je apparaat verwijdert, kan Ente je helpen mediabeheer in te stellen om herhaalde systeemmeldingen te vermijden. Ente kan ook je laatste verwijderkeuze onthouden.',
      localAndroidDeleteDesc:
          'Wanneer je iets van je apparaat verwijdert, kan Ente je helpen mediabeheer in te stellen om herhaalde systeemmeldingen te vermijden.',
      castTitle: 'Naar meerdere schermen casten',
      castDesc:
          'Je kunt albums nu naar meer dan één scherm tegelijk casten, actieve sessies bekijken en een specifieke sessie stoppen wanneer je klaar bent.',
      storageTitle: 'Betrouwbaardere opslagopruiming',
      storageDesc:
          'Ente verwijdert tijdelijke afbeeldings- en videobestanden nu betrouwbaarder, zodat de app geen extra opslagruimte op je apparaat blijft innemen.',
    ),
    'no': _ChangeLogFeatureStrings(
      deleteTitle: 'Enklere bekreftelser ved sletting',
      onlineAndroidDeleteDesc:
          'Når du sletter fra enheten, kan Ente hjelpe deg med å sette opp medieadministrasjon for å unngå gjentatte systemmeldinger. Ente kan også huske det siste slettevalget ditt.',
      localAndroidDeleteDesc:
          'Når du sletter fra enheten, kan Ente hjelpe deg med å sette opp medieadministrasjon for å unngå gjentatte systemmeldinger.',
      castTitle: 'Cast til flere skjermer',
      castDesc:
          'Du kan nå caste album til mer enn én skjerm om gangen, se aktive økter og stoppe en bestemt økt når du er ferdig.',
      storageTitle: 'Mer pålitelig lagringsopprydding',
      storageDesc:
          'Ente fjerner nå midlertidige bilde- og videofiler mer pålitelig, slik at appen ikke bruker ekstra lagringsplass på enheten.',
    ),
    'pl': _ChangeLogFeatureStrings(
      deleteTitle: 'Łatwiejsze potwierdzanie usuwania',
      onlineAndroidDeleteDesc:
          'Podczas usuwania z urządzenia Ente może pomóc skonfigurować zarządzanie multimediami, aby uniknąć powtarzających się monitów systemowych. Ente może też zapamiętać twój ostatni wybór usuwania.',
      localAndroidDeleteDesc:
          'Podczas usuwania z urządzenia Ente może pomóc skonfigurować zarządzanie multimediami, aby uniknąć powtarzających się monitów systemowych.',
      castTitle: 'Przesyłaj na wiele ekranów',
      castDesc:
          'Możesz teraz przesyłać albumy na więcej niż jeden ekran jednocześnie, wyświetlać aktywne sesje i zatrzymać wybraną sesję, gdy skończysz.',
      storageTitle: 'Bardziej niezawodne czyszczenie pamięci',
      storageDesc:
          'Ente teraz bardziej niezawodnie usuwa tymczasowe pliki obrazów i wideo, dzięki czemu aplikacja nie zajmuje dodatkowej pamięci urządzenia.',
    ),
    'pt_BR': _ChangeLogFeatureStrings(
      deleteTitle: 'Confirmações de exclusão mais fáceis',
      onlineAndroidDeleteDesc:
          'Ao excluir do seu dispositivo, o Ente pode ajudar você a configurar o gerenciamento de mídia para evitar avisos repetidos do sistema. O Ente também pode lembrar sua última escolha de exclusão.',
      localAndroidDeleteDesc:
          'Ao excluir do seu dispositivo, o Ente pode ajudar você a configurar o gerenciamento de mídia para evitar avisos repetidos do sistema.',
      castTitle: 'Transmitir para várias telas',
      castDesc:
          'Agora você pode transmitir álbuns para mais de uma tela ao mesmo tempo, ver sessões ativas e encerrar uma sessão específica quando terminar.',
      storageTitle: 'Limpeza de armazenamento mais confiável',
      storageDesc:
          'Agora o Ente limpa arquivos temporários de imagens e vídeos com mais confiabilidade, evitando que o app ocupe espaço extra no dispositivo.',
    ),
    'pt_PT': _ChangeLogFeatureStrings(
      deleteTitle: 'Confirmações de eliminação mais simples',
      onlineAndroidDeleteDesc:
          'Ao eliminar do seu dispositivo, o Ente pode ajudá-lo a configurar a gestão de multimédia para evitar avisos repetidos do sistema. O Ente também pode memorizar a sua última escolha de eliminação.',
      localAndroidDeleteDesc:
          'Ao eliminar do seu dispositivo, o Ente pode ajudá-lo a configurar a gestão de multimédia para evitar avisos repetidos do sistema.',
      castTitle: 'Transmitir para vários ecrãs',
      castDesc:
          'Agora pode transmitir álbuns para mais de um ecrã ao mesmo tempo, ver sessões ativas e parar uma sessão específica quando terminar.',
      storageTitle: 'Limpeza de armazenamento mais fiável',
      storageDesc:
          'O Ente limpa agora ficheiros temporários de imagens e vídeos de forma mais fiável, evitando que a app ocupe espaço extra no dispositivo.',
    ),
    'ro': _ChangeLogFeatureStrings(
      deleteTitle: 'Confirmări de ștergere mai simple',
      onlineAndroidDeleteDesc:
          'Când ștergi de pe dispozitiv, Ente te poate ajuta să configurezi gestionarea media pentru a evita solicitările repetate ale sistemului. Ente poate reține și ultima ta alegere de ștergere.',
      localAndroidDeleteDesc:
          'Când ștergi de pe dispozitiv, Ente te poate ajuta să configurezi gestionarea media pentru a evita solicitările repetate ale sistemului.',
      castTitle: 'Transmite pe mai multe ecrane',
      castDesc:
          'Acum poți transmite albume pe mai multe ecrane în același timp, poți vedea sesiunile active și poți opri o anumită sesiune când ai terminat.',
      storageTitle: 'Curățare mai fiabilă a stocării',
      storageDesc:
          'Ente curăță acum mai fiabil fișierele temporare de imagini și video, împiedicând aplicația să păstreze spațiu suplimentar pe dispozitiv.',
    ),
    'ru': _ChangeLogFeatureStrings(
      deleteTitle: 'Более простые подтверждения удаления',
      onlineAndroidDeleteDesc:
          'При удалении с устройства Ente может помочь настроить управление медиа, чтобы избежать повторяющихся системных запросов. Ente также может запомнить ваш последний выбор удаления.',
      localAndroidDeleteDesc:
          'При удалении с устройства Ente может помочь настроить управление медиа, чтобы избежать повторяющихся системных запросов.',
      castTitle: 'Трансляция на несколько экранов',
      castDesc:
          'Теперь вы можете транслировать альбомы сразу на несколько экранов, просматривать активные сеансы и останавливать нужный сеанс, когда закончите.',
      storageTitle: 'Более надежная очистка хранилища',
      storageDesc:
          'Теперь Ente надежнее удаляет временные файлы изображений и видео, чтобы приложение не занимало лишнее место в памяти устройства.',
    ),
    'tr': _ChangeLogFeatureStrings(
      deleteTitle: 'Daha kolay silme onayları',
      onlineAndroidDeleteDesc:
          'Cihazınızdan silerken Ente, tekrarlanan sistem istemlerini önlemek için medya yönetimini ayarlamanıza yardımcı olabilir. Ente son silme seçiminizi de hatırlayabilir.',
      localAndroidDeleteDesc:
          'Cihazınızdan silerken Ente, tekrarlanan sistem istemlerini önlemek için medya yönetimini ayarlamanıza yardımcı olabilir.',
      castTitle: 'Birden fazla ekrana yayınla',
      castDesc:
          'Artık albümleri aynı anda birden fazla ekrana yayınlayabilir, etkin oturumları görebilir ve işiniz bittiğinde belirli bir oturumu durdurabilirsiniz.',
      storageTitle: 'Daha güvenilir depolama temizliği',
      storageDesc:
          'Ente artık geçici görüntü ve video dosyalarını daha güvenilir şekilde temizleyerek uygulamanın cihazda fazladan depolama alanı tutmasını önler.',
    ),
    'uk': _ChangeLogFeatureStrings(
      deleteTitle: 'Простіші підтвердження видалення',
      onlineAndroidDeleteDesc:
          'Під час видалення з пристрою Ente може допомогти налаштувати керування медіа, щоб уникнути повторних системних запитів. Ente також може запам’ятати ваш останній вибір видалення.',
      localAndroidDeleteDesc:
          'Під час видалення з пристрою Ente може допомогти налаштувати керування медіа, щоб уникнути повторних системних запитів.',
      castTitle: 'Трансляція на кілька екранів',
      castDesc:
          'Тепер ви можете транслювати альбоми на кілька екранів одночасно, переглядати активні сеанси та зупиняти певний сеанс, коли завершите.',
      storageTitle: 'Надійніше очищення сховища',
      storageDesc:
          'Ente тепер надійніше очищує тимчасові файли зображень і відео, щоб застосунок не займав зайве місце у сховищі пристрою.',
    ),
    'vi': _ChangeLogFeatureStrings(
      deleteTitle: 'Xác nhận xóa dễ hơn',
      onlineAndroidDeleteDesc:
          'Khi xóa khỏi thiết bị, Ente có thể giúp bạn thiết lập quản lý phương tiện để tránh các lời nhắc hệ thống lặp lại. Ente cũng có thể ghi nhớ lựa chọn xóa gần nhất của bạn.',
      localAndroidDeleteDesc:
          'Khi xóa khỏi thiết bị, Ente có thể giúp bạn thiết lập quản lý phương tiện để tránh các lời nhắc hệ thống lặp lại.',
      castTitle: 'Truyền lên nhiều màn hình',
      castDesc:
          'Giờ bạn có thể truyền album lên nhiều màn hình cùng lúc, xem các phiên đang hoạt động và dừng một phiên cụ thể khi xong.',
      storageTitle: 'Dọn dẹp bộ nhớ đáng tin cậy hơn',
      storageDesc:
          'Ente giờ xóa các tệp ảnh và video tạm thời đáng tin cậy hơn, giúp ứng dụng không giữ thêm dung lượng lưu trữ trên thiết bị.',
    ),
    'zh_CN': _ChangeLogFeatureStrings(
      deleteTitle: '更轻松的删除确认',
      onlineAndroidDeleteDesc:
          '从设备删除时，Ente 可以帮助你设置媒体管理，避免重复的系统提示。Ente 还可以记住你上一次的删除选择。',
      localAndroidDeleteDesc: '从设备删除时，Ente 可以帮助你设置媒体管理，避免重复的系统提示。',
      castTitle: '投放到多个屏幕',
      castDesc: '你现在可以将相册同时投放到多个屏幕，查看活跃会话，并在完成后停止指定会话。',
      storageTitle: '更可靠的存储清理',
      storageDesc: 'Ente 现在会更可靠地清理临时图片和视频文件，避免应用占用额外的设备存储空间。',
    ),
  };
}

class _ChangeLogFeatureStrings {
  final String deleteTitle;
  final String onlineAndroidDeleteDesc;
  final String localAndroidDeleteDesc;
  final String castTitle;
  final String castDesc;
  final String storageTitle;
  final String storageDesc;

  const _ChangeLogFeatureStrings({
    required this.deleteTitle,
    required this.onlineAndroidDeleteDesc,
    required this.localAndroidDeleteDesc,
    required this.castTitle,
    required this.castDesc,
    required this.storageTitle,
    required this.storageDesc,
  });
}

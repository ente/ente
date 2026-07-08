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
      title1: 'Easier delete confirmations',
      desc1:
          'Deleting photos now takes fewer taps. We replaced multiple prompts with one confirmation sheet that remembers your last choice.',
      title2: 'Cast to multiple screens',
      desc2:
          "You can now cast albums to more than one screen at a time, view active sessions, and stop a specific session when you're done.",
      title3: 'More reliable storage cleanup',
      desc3:
          'Ente now clears temporary image and video files more reliably, keeping the app from holding on to extra device storage.',
    ),
    'cs': ChangeLogStrings(
      title1: 'Snazší potvrzení odstranění',
      desc1:
          'Odstranění fotek teď vyžaduje méně klepnutí. Několik výzev jsme nahradili jedním potvrzovacím panelem, který si pamatuje vaši poslední volbu.',
      title2: 'Promítání na více obrazovek',
      desc2:
          'Alba teď můžete promítat na více obrazovek najednou, zobrazit aktivní relace a po skončení zastavit konkrétní relaci.',
      title3: 'Spolehlivější čištění úložiště',
      desc3:
          'Ente teď spolehlivěji odstraňuje dočasné soubory obrázků a videí, takže aplikace nezabírá zbytečně další místo v úložišti zařízení.',
    ),
    'de': ChangeLogStrings(
      title1: 'Einfachere Löschbestätigungen',
      desc1:
          'Das Löschen von Fotos braucht jetzt weniger Fingertipps. Wir haben mehrere Abfragen durch einen einzigen Bestätigungsdialog ersetzt, der sich deine letzte Auswahl merkt.',
      title2: 'Auf mehrere Bildschirme streamen',
      desc2:
          'Du kannst Alben jetzt auf mehr als einen Bildschirm gleichzeitig streamen, aktive Sitzungen anzeigen und eine bestimmte Sitzung beenden, wenn du fertig bist.',
      title3: 'Zuverlässigere Speicherbereinigung',
      desc3:
          'Ente entfernt temporäre Bild- und Videodateien jetzt zuverlässiger, damit die App keinen zusätzlichen Gerätespeicher belegt.',
    ),
    'es': ChangeLogStrings(
      title1: 'Confirmaciones de eliminación más sencillas',
      desc1:
          'Eliminar fotos ahora requiere menos toques. Sustituimos varias solicitudes por un único panel de confirmación que recuerda tu última elección.',
      title2: 'Transmitir a varias pantallas',
      desc2:
          'Ahora puedes transmitir álbumes a más de una pantalla a la vez, ver las sesiones activas y detener una sesión específica cuando termines.',
      title3: 'Limpieza de almacenamiento más fiable',
      desc3:
          'Ente ahora elimina los archivos temporales de imágenes y videos con mayor fiabilidad, evitando que la app retenga almacenamiento adicional del dispositivo.',
    ),
    'fr': ChangeLogStrings(
      title1: 'Confirmations de suppression plus simples',
      desc1:
          'Supprimer des photos demande maintenant moins d’appuis. Nous avons remplacé plusieurs invites par un seul panneau de confirmation qui mémorise votre dernier choix.',
      title2: 'Diffuser sur plusieurs écrans',
      desc2:
          'Vous pouvez maintenant diffuser des albums sur plusieurs écrans à la fois, voir les sessions actives et arrêter une session précise lorsque vous avez terminé.',
      title3: 'Nettoyage du stockage plus fiable',
      desc3:
          'Ente supprime désormais les fichiers temporaires d’images et de vidéos de manière plus fiable, afin que l’app n’occupe pas inutilement de l’espace sur votre appareil.',
    ),
    'it': ChangeLogStrings(
      title1: 'Conferme di eliminazione più semplici',
      desc1:
          'Eliminare le foto ora richiede meno tocchi. Abbiamo sostituito più richieste con un unico pannello di conferma che ricorda la tua ultima scelta.',
      title2: 'Trasmetti su più schermi',
      desc2:
          'Ora puoi trasmettere gli album su più di uno schermo alla volta, vedere le sessioni attive e interrompere una sessione specifica quando hai finito.',
      title3: 'Pulizia dello spazio più affidabile',
      desc3:
          "Ente ora elimina i file temporanei di immagini e video in modo più affidabile, evitando che l'app trattenga spazio extra sul dispositivo.",
    ),
    'ja': ChangeLogStrings(
      title1: '削除確認がより簡単に',
      desc1: '写真の削除に必要なタップ数が減りました。複数の確認画面を、最後に選んだ内容を記憶する1つの確認シートに置き換えました。',
      title2: '複数の画面にキャスト',
      desc2:
          'アルバムを複数の画面に同時にキャストし、アクティブなセッションを確認して、終了したい特定のセッションだけを停止できるようになりました。',
      title3: 'ストレージクリーンアップの信頼性向上',
      desc3: 'Ente は一時的な画像ファイルと動画ファイルをより確実に削除し、アプリが余分なデバイスストレージを使い続けないようにします。',
    ),
    'nl': ChangeLogStrings(
      title1: 'Eenvoudigere verwijderbevestigingen',
      desc1:
          "Foto's verwijderen kost nu minder tikken. We hebben meerdere meldingen vervangen door één bevestigingsvenster dat je laatste keuze onthoudt.",
      title2: 'Naar meerdere schermen casten',
      desc2:
          'Je kunt albums nu naar meer dan één scherm tegelijk casten, actieve sessies bekijken en een specifieke sessie stoppen wanneer je klaar bent.',
      title3: 'Betrouwbaardere opslagopruiming',
      desc3:
          'Ente verwijdert tijdelijke afbeeldings- en videobestanden nu betrouwbaarder, zodat de app geen extra opslagruimte op je apparaat blijft innemen.',
    ),
    'no': ChangeLogStrings(
      title1: 'Enklere bekreftelser ved sletting',
      desc1:
          'Det krever nå færre trykk å slette bilder. Vi har erstattet flere spørsmål med én bekreftelsesdialog som husker det siste valget ditt.',
      title2: 'Cast til flere skjermer',
      desc2:
          'Du kan nå caste album til mer enn én skjerm om gangen, se aktive økter og stoppe en bestemt økt når du er ferdig.',
      title3: 'Mer pålitelig lagringsopprydding',
      desc3:
          'Ente fjerner nå midlertidige bilde- og videofiler mer pålitelig, slik at appen ikke bruker ekstra lagringsplass på enheten.',
    ),
    'pl': ChangeLogStrings(
      title1: 'Łatwiejsze potwierdzanie usuwania',
      desc1:
          'Usuwanie zdjęć wymaga teraz mniej stuknięć. Zastąpiliśmy kilka monitów jednym panelem potwierdzenia, który zapamiętuje ostatni wybór.',
      title2: 'Przesyłaj na wiele ekranów',
      desc2:
          'Możesz teraz przesyłać albumy na więcej niż jeden ekran jednocześnie, wyświetlać aktywne sesje i zatrzymać wybraną sesję, gdy skończysz.',
      title3: 'Bardziej niezawodne czyszczenie pamięci',
      desc3:
          'Ente teraz bardziej niezawodnie usuwa tymczasowe pliki obrazów i wideo, dzięki czemu aplikacja nie zajmuje dodatkowej pamięci urządzenia.',
    ),
    'pt_BR': ChangeLogStrings(
      title1: 'Confirmações de exclusão mais fáceis',
      desc1:
          'Excluir fotos agora exige menos toques. Substituímos vários avisos por uma única tela de confirmação que lembra sua última escolha.',
      title2: 'Transmitir para várias telas',
      desc2:
          'Agora você pode transmitir álbuns para mais de uma tela ao mesmo tempo, ver sessões ativas e encerrar uma sessão específica quando terminar.',
      title3: 'Limpeza de armazenamento mais confiável',
      desc3:
          'Agora o Ente limpa arquivos temporários de imagens e vídeos com mais confiabilidade, evitando que o app ocupe espaço extra no dispositivo.',
    ),
    'pt_PT': ChangeLogStrings(
      title1: 'Confirmações de eliminação mais simples',
      desc1:
          'Eliminar fotografias requer agora menos toques. Substituímos vários avisos por um único painel de confirmação que memoriza a sua última escolha.',
      title2: 'Transmitir para vários ecrãs',
      desc2:
          'Agora pode transmitir álbuns para mais de um ecrã ao mesmo tempo, ver sessões ativas e parar uma sessão específica quando terminar.',
      title3: 'Limpeza de armazenamento mais fiável',
      desc3:
          'O Ente limpa agora ficheiros temporários de imagens e vídeos de forma mais fiável, evitando que a app ocupe espaço extra no dispositivo.',
    ),
    'ro': ChangeLogStrings(
      title1: 'Confirmări de ștergere mai simple',
      desc1:
          'Ștergerea fotografiilor necesită acum mai puține atingeri. Am înlocuit mai multe solicitări cu un singur panou de confirmare care reține ultima ta alegere.',
      title2: 'Transmite pe mai multe ecrane',
      desc2:
          'Acum poți transmite albume pe mai multe ecrane în același timp, poți vedea sesiunile active și poți opri o anumită sesiune când ai terminat.',
      title3: 'Curățare mai fiabilă a stocării',
      desc3:
          'Ente curăță acum mai fiabil fișierele temporare de imagini și video, împiedicând aplicația să păstreze spațiu suplimentar pe dispozitiv.',
    ),
    'ru': ChangeLogStrings(
      title1: 'Более простые подтверждения удаления',
      desc1:
          'Удаление фотографий теперь требует меньше нажатий. Мы заменили несколько запросов одним окном подтверждения, которое запоминает ваш последний выбор.',
      title2: 'Трансляция на несколько экранов',
      desc2:
          'Теперь вы можете транслировать альбомы сразу на несколько экранов, просматривать активные сеансы и останавливать нужный сеанс, когда закончите.',
      title3: 'Более надежная очистка хранилища',
      desc3:
          'Теперь Ente надежнее удаляет временные файлы изображений и видео, чтобы приложение не занимало лишнее место в памяти устройства.',
    ),
    'tr': ChangeLogStrings(
      title1: 'Daha kolay silme onayları',
      desc1:
          'Fotoğraf silmek artık daha az dokunuş gerektiriyor. Birden fazla istemi, son seçiminizi hatırlayan tek bir onay ekranıyla değiştirdik.',
      title2: 'Birden fazla ekrana yayınla',
      desc2:
          'Artık albümleri aynı anda birden fazla ekrana yayınlayabilir, etkin oturumları görebilir ve işiniz bittiğinde belirli bir oturumu durdurabilirsiniz.',
      title3: 'Daha güvenilir depolama temizliği',
      desc3:
          'Ente artık geçici görüntü ve video dosyalarını daha güvenilir şekilde temizleyerek uygulamanın cihazda fazladan depolama alanı tutmasını önler.',
    ),
    'uk': ChangeLogStrings(
      title1: 'Простіші підтвердження видалення',
      desc1:
          'Видалення фотографій тепер потребує менше дотиків. Ми замінили кілька запитів одним вікном підтвердження, яке запам’ятовує ваш останній вибір.',
      title2: 'Трансляція на кілька екранів',
      desc2:
          'Тепер ви можете транслювати альбоми на кілька екранів одночасно, переглядати активні сеанси та зупиняти певний сеанс, коли завершите.',
      title3: 'Надійніше очищення сховища',
      desc3:
          'Ente тепер надійніше очищує тимчасові файли зображень і відео, щоб застосунок не займав зайве місце у сховищі пристрою.',
    ),
    'vi': ChangeLogStrings(
      title1: 'Xác nhận xóa dễ hơn',
      desc1:
          'Việc xóa ảnh giờ cần ít lần chạm hơn. Chúng tôi đã thay nhiều lời nhắc bằng một bảng xác nhận duy nhất có thể ghi nhớ lựa chọn gần nhất của bạn.',
      title2: 'Truyền lên nhiều màn hình',
      desc2:
          'Giờ bạn có thể truyền album lên nhiều màn hình cùng lúc, xem các phiên đang hoạt động và dừng một phiên cụ thể khi xong.',
      title3: 'Dọn dẹp bộ nhớ đáng tin cậy hơn',
      desc3:
          'Ente giờ xóa các tệp ảnh và video tạm thời đáng tin cậy hơn, giúp ứng dụng không giữ thêm dung lượng lưu trữ trên thiết bị.',
    ),
    'zh_CN': ChangeLogStrings(
      title1: '更轻松的删除确认',
      desc1: '删除照片现在只需更少点击。我们将多个提示替换为一个确认面板，并会记住你上一次的选择。',
      title2: '投放到多个屏幕',
      desc2: '你现在可以将相册同时投放到多个屏幕，查看活跃会话，并在完成后停止指定会话。',
      title3: '更可靠的存储清理',
      desc3: 'Ente 现在会更可靠地清理临时图片和视频文件，避免应用占用额外的设备存储空间。',
    ),
  };

  static const Map<String, ChangeLogStrings> _offlineTranslations = {};
}

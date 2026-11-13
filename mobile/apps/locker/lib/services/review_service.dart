import 'dart:io';

import 'package:locker/services/update_service.dart';

abstract final class ReviewService {
  static String get url {
    if (Platform.isIOS) {
      return 'https://apps.apple.com/app/ente-locker/id6747611956';
    }
    if (UpdateService.instance.isPlayStoreFlavor()) {
      return 'https://play.google.com/store/apps/details?id=io.ente.locker';
    }
    return 'https://alternativeto.net/software/ente-locker/about/';
  }
}

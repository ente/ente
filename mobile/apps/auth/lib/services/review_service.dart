import 'dart:io';

import 'package:flutter/services.dart' show appFlavor;

abstract final class ReviewService {
  static String get url {
    if (Platform.isIOS) {
      return 'https://apps.apple.com/app/id6444121398';
    }
    if (Platform.isAndroid && appFlavor == 'playstore') {
      return 'https://play.google.com/store/apps/details?id=io.ente.auth';
    }
    return 'https://alternativeto.net/software/ente-authenticator/about/';
  }
}

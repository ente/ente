import 'dart:io';

import 'package:photos/service_locator.dart';
import 'package:url_launcher/url_launcher_string.dart';

abstract final class ReviewService {
  static String get url {
    if (Platform.isIOS) {
      return 'https://apps.apple.com/app/ente-photos/id1542026904';
    }
    if (updateService.isPlayStoreFlavor()) {
      return 'https://play.google.com/store/apps/details?id=io.ente.photos';
    }
    return 'https://alternativeto.net/software/ente/about/';
  }

  static Future<void> launch() {
    return launchUrlString(url, mode: LaunchMode.externalApplication);
  }
}

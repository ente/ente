import 'dart:io';

import 'package:ente_qr/ente_qr_platform_interface.dart';
import 'package:ente_qr/src/dart_zxing_qr_platform.dart';

EnteQrPlatform? desktopQrPlatform() {
  if (Platform.isWindows || Platform.isLinux) {
    return DartZxingQrPlatform();
  }
  return null;
}

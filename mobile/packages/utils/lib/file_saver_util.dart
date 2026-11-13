import 'dart:io';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';

class FileSaverUtil {
  static Future<bool> saveFile(
    String fileName,
    String extension,
    Uint8List bytes,
    MimeType type,
  ) async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final savedPath = await FileSaver.instance.saveAs(
          name: fileName,
          fileExtension: extension,
          bytes: bytes,
          mimeType: type,
        );
        return savedPath != null;
      } else {
        await FileSaver.instance.saveFile(
          name: fileName,
          fileExtension: extension,
          bytes: bytes,
          mimeType: type,
        );
        return true;
      }
    } catch (_) {
      return false;
    }
  }
}

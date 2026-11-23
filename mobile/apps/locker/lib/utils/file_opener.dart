import 'package:flutter/services.dart';

enum FileOpenerResultType { done, noAppToOpen, fileNotFound, error }

class FileOpenerResult {
  final FileOpenerResultType type;
  final String? message;

  const FileOpenerResult({required this.type, this.message});
}

class LockerFileOpener {
  static const MethodChannel _channel = MethodChannel(
    'io.ente.locker/file_opener',
  );

  static Future<FileOpenerResult> open(String filePath) async {
    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'openFile',
        {'filePath': filePath},
      );

      final resultTypeStr = response?['resultType'] as String?;
      final message = response?['message'] as String?;

      final type = switch (resultTypeStr) {
        'done' => FileOpenerResultType.done,
        'noAppToOpen' => FileOpenerResultType.noAppToOpen,
        'fileNotFound' => FileOpenerResultType.fileNotFound,
        _ => FileOpenerResultType.error,
      };

      return FileOpenerResult(type: type, message: message);
    } on PlatformException catch (e) {
      return FileOpenerResult(
        type: FileOpenerResultType.error,
        message: e.message,
      );
    } catch (e) {
      return FileOpenerResult(
        type: FileOpenerResultType.error,
        message: e.toString(),
      );
    }
  }
}

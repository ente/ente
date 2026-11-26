import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/utils/file_opener.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('io.ente.locker/file_opener');

  group('LockerFileOpener', () {
    test('returns done when native call succeeds', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            if (call.method == 'openFile') {
              expect(call.arguments, {'filePath': '/path/to/test.pdf'});
              return {'resultType': 'done', 'message': 'done'};
            }
            return null;
          });

      final result = await LockerFileOpener.open('/path/to/test.pdf');
      expect(result.type, FileOpenerResultType.done);
      expect(result.message, 'done');
    });

    test('returns noAppToOpen when no app is available', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            if (call.method == 'openFile') {
              return {'resultType': 'noAppToOpen', 'message': 'No app found'};
            }
            return null;
          });

      final result = await LockerFileOpener.open('/path/to/test.kdbx');
      expect(result.type, FileOpenerResultType.noAppToOpen);
      expect(result.message, 'No app found');
    });

    test('returns fileNotFound when file does not exist', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            if (call.method == 'openFile') {
              return {
                'resultType': 'fileNotFound',
                'message': 'File does not exist',
              };
            }
            return null;
          });

      final result = await LockerFileOpener.open('/path/to/missing.bin');
      expect(result.type, FileOpenerResultType.fileNotFound);
      expect(result.message, 'File does not exist');
    });

    test('returns error on PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            throw PlatformException(code: 'ERR', message: 'Failed to launch');
          });

      final result = await LockerFileOpener.open('/path/to/test.pdf');
      expect(result.type, FileOpenerResultType.error);
      expect(result.message, 'Failed to launch');
    });
  });
}

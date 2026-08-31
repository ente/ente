import 'package:backup_exclusion/backup_exclusion.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('io.ente.backup_exclusion');
  const testPath = '/var/mobile/Containers/Data/Application/test/Documents';

  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('invokeExcludeFromBackup', () {
    test(
      'invokes excludeFromBackup on the correct channel with the given path',
      () async {
        await invokeExcludeFromBackup(testPath);

        expect(calls, hasLength(1));
        expect(calls.first.method, 'excludeFromBackup');
        expect(calls.first.arguments, {'path': testPath});
      },
    );

    test('logs a warning when the channel throws PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            throw PlatformException(
              code: 'EXCLUDE_BACKUP_ERROR',
              message: 'simulated native failure',
            );
          });

      final logs = <LogRecord>[];
      final sub = Logger('BackupExclusion').onRecord.listen(logs.add);

      await invokeExcludeFromBackup(testPath);

      await sub.cancel();
      expect(
        logs.any(
          (r) =>
              r.level == Level.WARNING &&
              r.message.contains('Failed to exclude path from backup'),
        ),
        isTrue,
      );
    });

    test('logs info and does not throw when channel is unregistered '
        '(MissingPluginException - headless background)', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);

      final logs = <LogRecord>[];
      final sub = Logger('BackupExclusion').onRecord.listen(logs.add);

      await expectLater(invokeExcludeFromBackup(testPath), completes);

      await sub.cancel();
      expect(
        logs.any(
          (r) =>
              r.level == Level.INFO &&
              r.message.contains('channel unavailable'),
        ),
        isTrue,
      );
    });
  });

  group('excludeFromBackup (platform guard)', () {
    test('does not invoke the channel on non-iOS platforms', () async {
      await excludeFromBackup(testPath);
      expect(calls, isEmpty);
    });
  });
}

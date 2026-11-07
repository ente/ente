import 'package:ente_photos_platform/ente_photos_platform.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(
    'io.ente.photos.platform/device_folder_transfer',
  );
  const client = DeviceFolderTransferClient();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'keeps successful files separate from failed or cancelled files',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'deviceFolderTransfer.transfer');
        expect(call.arguments, {
          'operation': 'move',
          'sourceFolderID': 'source',
          'targetFolderID': 'target',
          'sourceLocalIDs': ['1', '2', '3'],
        });
        return {
          'destinations': {'1': '1'},
          'failures': {'2': 'cancelled', '3': 'permissionDenied'},
        };
      });
      final result = await client.transfer(
        operation: DeviceFolderTransferOperation.move,
        sourceFolderID: 'source',
        targetFolderID: 'target',
        sourceLocalIDs: ['1', '2', '3'],
      );
      expect(result.destinations, {'1': '1'});
      expect(result.failures.keys.toSet(), {'2', '3'});
      expect(result.wasCancelled, isFalse);
    },
  );

  test('recognizes cancellation only when no files completed', () {
    final cancelled = DeviceFolderTransferResult.fromChannelMap({
      'destinations': <String, dynamic>{},
      'failures': {'1': 'cancelled'},
    });
    expect(cancelled.wasCancelled, isTrue);
    final unknownFailure = DeviceFolderTransferResult.fromChannelMap({
      'destinations': <String, dynamic>{},
      'failures': {'1': 'futureFailure'},
    });
    expect(unknownFailure.wasCancelled, isFalse);
    expect(unknownFailure.failures['1'], DeviceFolderTransferFailure.failed);
  });

  test('does not treat a missing native response as success', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(
      () => client.transfer(
        operation: DeviceFolderTransferOperation.add,
        sourceFolderID: 'source',
        targetFolderID: 'target',
        sourceLocalIDs: ['1'],
      ),
      throwsA(isA<PlatformException>()),
    );
  });
}

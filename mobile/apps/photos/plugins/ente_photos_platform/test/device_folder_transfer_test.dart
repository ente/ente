import 'package:ente_photos_platform/ente_photos_platform.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('passes operation while loading destinations', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('device-folder-transfer-test');
    MethodCall? receivedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          receivedCall = call;
          return ['destination'];
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final result = await DeviceFolderTransferClient(methodChannel: channel)
        .eligibleDestinationIDs(
          sourceFolderID: 'source',
          operation: DeviceFolderTransferOperation.move,
          sourceLocalIDs: ['file-1'],
          candidateFolderIDs: ['destination'],
        );

    expect(result, {'destination'});
    expect(
      receivedCall?.arguments,
      containsPair('operation', DeviceFolderTransferOperation.move.name),
    );
  });

  test('decodes the native operation capability set', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('device-folder-transfer-capabilities-test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'deviceFolderTransfer.supportedOperations');
          return ['copy', 'unknown'];
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final supported = await DeviceFolderTransferClient(
      methodChannel: channel,
    ).supportedOperations();

    expect(supported, {DeviceFolderTransferOperation.copy});
  });

  test('decodes valid per-file transfer outcomes', () {
    final result = DeviceFolderTransferResult.fromChannelMap({
      'destinations': {
        'one': {'localID': 'new-one'},
      },
      'failures': {'two': 'missingSource', 'three': 'unknown'},
    });

    expect(result.successLocalIDs, {'one'});
    expect(result.destinations, {'one': 'new-one'});
    expect(result.destinations['one'], 'new-one');
    expect(result.failures['two'], DeviceFolderTransferFailure.missingSource);
    expect(result.failures['three'], DeviceFolderTransferFailure.failed);
  });

  test('recognizes a fully cancelled transfer', () {
    final result = DeviceFolderTransferResult.fromChannelMap({
      'successLocalIDs': <String>[],
      'failures': {'one': 'cancelled', 'two': 'cancelled'},
    });

    expect(result.wasCancelled, isTrue);
  });
}

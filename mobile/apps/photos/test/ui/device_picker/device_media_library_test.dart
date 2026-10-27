import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photos/ui/device_picker/device_media_library.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'album queries keep media regardless of dimensions or creation date',
    () async {
      const channel = MethodChannel('com.fluttercandies/photo_manager');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        final arguments = call.arguments as Map;
        final filter = (arguments['option'] as Map)['child'] as Map;
        expect(arguments['type'], RequestType.common.value);
        for (final type in ['image', 'video']) {
          expect(((filter[type] as Map)['size'] as Map)['ignoreSize'], isTrue);
        }
        expect((filter['createDate'] as Map)['ignore'], isTrue);
        return switch (call.method) {
          'getAssetPathList' => {
            'data': [
              {'id': 'recent', 'name': 'Recent', 'isAll': true},
            ],
          },
          'getAssetCountFromPath' => 1,
          'getAssetListRange' => {'data': []},
          _ => throw StateError(
            'Unexpected photo manager call: ${call.method}',
          ),
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final library = PhotoManagerDeviceLibrary();
      final album = (await library.albums()).single;
      expect(await library.count(album), 1);
      expect(await library.read(album, start: 0, end: 1), isEmpty);
    },
  );
}

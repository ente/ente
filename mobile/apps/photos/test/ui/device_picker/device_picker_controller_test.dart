import "dart:async";

import "package:flutter_test/flutter_test.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photos/ui/device_picker/device_picker_controller.dart";

import "device_picker_test_helpers.dart";

void main() {
  late FakeDeviceLibrary library;
  late DevicePickerController model;

  setUp(() {
    library = FakeDeviceLibrary();
    model = DevicePickerController(library: library);
  });
  tearDown(() => model.dispose());

  test(
    'selection stops at 50 and confirmation resolves in bounded batches',
    () async {
      library.items = List.generate(80, (i) => media('$i'));
      await model.refresh();
      var running = 0;
      var peak = 0;
      library.resolveOverride = (id) async {
        running++;
        if (running > peak) peak = running;
        await Future<void>.delayed(Duration.zero);
        running--;
        return library.items[int.parse(id)];
      };
      model.replaceSelection(library.items);
      expect(model.selectionCount, 50);
      model.replaceSelection([
        ...model.selection.where((item) => item.id != '10'),
        library.items[50],
      ]);
      expect(model.selectionCount, 50);
      final confirmed = await model.confirm();
      expect(confirmed, model.selection);
      expect(identical(confirmed!.first, library.items.first), isTrue);
      expect(peak, lessThanOrEqualTo(8));
    },
  );

  test(
    'leaving during a large confirmation cancels the remaining batches',
    () async {
      library.items = List.generate(100, (i) => media('$i'));
      final controller = DevicePickerController(library: library);
      await controller.refresh();
      controller.replaceSelection(library.items);
      final pending = Completer<AssetEntity?>();
      var requests = 0;
      library.resolveOverride = (_) {
        requests++;
        return pending.future;
      };
      final confirmation = controller.confirm();
      controller.dispose();
      pending.complete(null);
      expect(await confirmation, isNull);
      expect(requests, 8);
    },
  );

  test('late page from the old album cannot replace the new album', () async {
    library.items = List.generate(100, (index) => media('$index'));
    await model.refresh();
    model.replaceSelection([library.items.first]);
    final pending = Completer<List<AssetEntity>>();
    library.readOverride = (album, start, end) {
      if (album.id == 'recent' && start > 0) return pending.future;
      return Future.value([media('new-album')]);
    };
    final oldPage = model.loadMore();
    await model.openAlbum(library.folders.last);
    pending.complete([media('old-album')]);
    await oldPage;
    expect(model.media.single.id, 'new-album');
    expect(model.loadingMore, isFalse);
    expect(model.selection, [library.items.first]);
  });

  test('a failed page can be retried without losing selection', () async {
    library.items = List.generate(100, (index) => media('$index'));
    await model.refresh();
    model.replaceSelection([library.items.first]);
    library.readOverride = (_, _, _) => Future.error(StateError('offline'));
    await model.loadMore();
    expect(model.error, isNotNull);
    expect(model.media.length, 96);
    library.readOverride = null;
    await model.loadMore();
    expect(model.error, isNull);
    expect(model.media.length, 100);
    expect(model.selection.single.id, '0');
  });

  test(
    'failed album refresh keeps its snapshot and retries from the start',
    () async {
      library.items = List.generate(100, (index) => media('old-$index'));
      await model.refresh();
      library.folders.removeAt(0);
      library.readOverride = (_, _, _) =>
          Future.error(StateError('Unavailable'));
      await model.refresh();
      expect(model.album!.id, 'recent');
      expect(model.media.first.id, 'old-0');
      expect(model.media.length, 96);
      expect(model.hasMore, isFalse);
      expect(model.error, isNotNull);

      final starts = <int>[];
      final replacement = List.generate(100, (index) => media('new-$index'));
      library.readOverride = (album, start, end) async {
        expect(album.id, 'camera');
        starts.add(start);
        return replacement.skip(start).take(end - start).toList();
      };
      await model.refresh();
      expect(model.album!.id, 'camera');
      expect(model.media, replacement.take(96));
      expect(model.error, isNull);
      await model.loadMore();
      expect(starts, [0, 96]);
      expect(model.media, replacement);
    },
  );

  test(
    'confirmation removes unavailable selections and requires review',
    () async {
      await model.refresh();
      model.replaceSelection(library.items.take(2));
      library.unavailable.add(library.items.first.id);
      expect(await model.confirm(), isNull);
      expect(model.removedSelections, 1);
      expect(model.selection.single.id, library.items[1].id);
      expect(await model.confirm(), [library.items[1]]);
    },
  );

  test('permission revocation clears cached media and selection', () async {
    await model.refresh();
    model.replaceSelection([library.items.first]);
    library.access = PermissionState.denied;
    await model.refresh();
    expect(model.hasAccess, isFalse);
    expect(model.media, isEmpty);
    expect(model.selection, isEmpty);
    expect(await model.confirm(), isNull);
  });

  test('failed confirmation keeps selection available for retry', () async {
    await model.refresh();
    model.replaceSelection([library.items.first]);
    library.resolveOverride = (_) => Future.error(StateError('Unavailable'));
    await expectLater(model.confirm(), throwsStateError);
    expect(model.confirming, isFalse);
    expect(model.error, isNull);
    expect(model.selection, [library.items.first]);
    library.resolveOverride = null;
    expect(await model.confirm(), [library.items.first]);
  });

  test(
    'selection made during refresh is not mistaken for a missing asset',
    () async {
      await model.refresh();
      model.replaceSelection([library.items.first]);
      final pending = Completer<AssetEntity?>();
      library.resolveOverride = (_) => pending.future;
      final refresh = model.refresh();
      await Future<void>.delayed(Duration.zero);
      model.replaceSelection([...model.selection, library.items[1]]);
      pending.complete(library.items.first);
      await refresh;
      expect(model.selection.length, 2);
      expect(model.removedSelections, 0);
    },
  );
}

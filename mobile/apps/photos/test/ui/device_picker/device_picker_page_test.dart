import "dart:async";
import "dart:io";

import "package:dio/dio.dart";
import "package:ente_components/components/buttons/button_component.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_easyloading/flutter_easyloading.dart";
import "package:flutter_test/flutter_test.dart";
import "package:media_extension/media_extension_action_types.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photos/app_mode.dart";
import "package:photos/core/cache/image_cache.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/constants.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/module/metadata/local_file.dart";
import "package:photos/service_locator.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/states/detail_page_state.dart";
import "package:photos/ui/components/bottom_action_bar/action_bar_widget.dart";
import "package:photos/ui/components/selection_preview_button.dart";
import "package:photos/ui/device_picker/device_picker_gallery.dart";
import "package:photos/ui/device_picker/device_picker_page.dart";
import "package:photos/ui/picker/external_media_picker_page.dart";
import "package:photos/ui/viewer/file/detail_page.dart";
import "package:photos/ui/viewer/file/file_widget.dart";
import "package:photos/ui/viewer/file/image_zoom/image_zoom_viewer.dart";
import "package:photos/ui/viewer/gallery/component/gallery_file_widget.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:shared_preferences/shared_preferences.dart";

import "device_picker_test_helpers.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final navigatorKey = GlobalKey<NavigatorState>();
  late FakeDeviceLibrary library;
  late Future<List<AssetEntity>?> result;
  var firstPhotoTrashed = false;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    ServiceLocator.instance.init(
      preferences,
      Dio(),
      Dio(),
      Dio(),
      PackageInfo(
        appName: 'Photos',
        packageName: 'photos',
        version: '1',
        buildNumber: '1',
      ),
    );
    try {
      await Configuration.instance.init(preferences);
    } catch (_) {}

    final fonts = FontLoader('packages/ente_components/Inter');
    for (final name in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      fonts.addFont(
        rootBundle.load('packages/ente_components/fonts/Inter-$name.ttf'),
      );
    }
    await fonts.load();

    final bytes = File('assets/memories.jpg').readAsBytesSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.fluttercandies/photo_manager'),
          (call) async {
            final args = call.arguments;
            final id = args is Map ? args['id'] as String? : null;
            if (call.method == 'getAssetPathList') {
              expect((args as Map)['type'], RequestType.image.value);
            }
            return switch (call.method) {
              'requestPermissionExtend' => PermissionState.authorized.index,
              'getAssetPathList' => {
                'data': [
                  {'id': 'recent', 'name': 'Recent', 'isAll': true},
                  {'id': 'camera', 'name': 'Camera', 'isAll': false},
                ],
              },
              'getAssetCountFromPath' => id == 'recent' ? 3 : 1,
              'getAssetListRange' || 'getAssetListPaged' => {
                'data': [
                  if (id == 'recent' && !firstPhotoTrashed) _assetData('0'),
                  if (id == 'recent') _assetData('1'),
                  _assetData('2'),
                ],
              },
              'fetchEntityProperties' => _assetData(id!),
              'getMediaUrl' => 'content://media/external/images/media/$id',
              'getThumb' || 'getOriginBytes' => bytes,
              'assetExists' => true,
              _ => null,
            };
          },
        );
  });

  setUp(() async {
    firstPhotoTrashed = false;
    await localSettings.setGalleryLayoutType(GalleryLayoutType.grid);
    await localSettings.setPhotoGridSize(5);
    await localSettings.setAppMode(AppMode.localGallery);
    library = FakeDeviceLibrary()
      ..items = List.generate(160, (index) => media('$index'));
  });

  Future<void> mount(
    WidgetTester tester, {
    bool withParentRoute = false,
    Size size = const Size(390, 844),
    double textScale = 1,
    String locale = 'en',
    int? selectionLimit = maxPickAssetLimit,
    bool allowEmptySelection = false,
    Iterable<AssetEntity> initialSelection = const [],
    Widget? picker,
  }) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        locale: Locale(locale),
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: StringsLocalizations.supportedLocales,
        theme: lightThemeData,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: EasyLoading.init()(context, child),
        ),
        home: const Scaffold(),
      ),
    );
    if (withParentRoute) {
      unawaited(
        navigatorKey.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Album')),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }
    result = navigatorKey.currentState!.push<List<AssetEntity>>(
      MaterialPageRoute(
        builder: (_) =>
            picker ??
            DevicePickerPage(
              library: library,
              selectionLimit: selectionLimit,
              allowEmptySelection: allowEmptySelection,
              initialSelection: initialSelection,
            ),
      ),
    );
    await _settleImages(tester);
    await tester.pump(const Duration(seconds: 5));
  }

  tearDown(() async {
    await EasyLoading.dismiss(animation: false);
    FileLruCache.clearAll();
  });

  testWidgets(
    'local external picker shares selection across Photos and folders',
    (tester) async {
      final paths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _NoLocalDatabase();
      addTearDown(() => PathProviderPlatform.instance = paths);
      tester.view.systemGestureInsets = const FakeViewPadding(left: 24);
      addTearDown(tester.view.resetSystemGestureInsets);
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('media_extension'),
        (call) async => calls.add(call),
      );
      for (final allowMultiple in [false, true]) {
        await mount(
          tester,
          picker: ExternalMediaPickerPage(
            requestedType: MediaType.image,
            allowMultiple: allowMultiple,
          ),
        );
        final tiles = find.byType(GalleryFileWidget);
        final grid = find.byType(DevicePickerGallery);
        expect(
          GalleryBoundariesProvider.of(
            tester.element(grid),
          )!.topBoundaryNotifier.value,
          tester.getTopLeft(grid).dy,
        );
        await tester.tap(tiles.first);
        if (allowMultiple) {
          final edge = Offset(1, tester.getCenter(tiles.first).dy);
          await tester.timedDragFrom(
            edge,
            tester.getCenter(tiles.at(2)) - edge,
            const Duration(milliseconds: 200),
          );
          await tester.pump();
          expect(find.widgetWithText(SelectionPreviewButton, '1'), findsOne);
          await tester.tap(tiles.at(1));
        }
        await tester.tap(find.text('Albums'));
        await _settleImages(tester);
        await tester.tap(find.text('Camera'));
        await _settleImages(tester);
        await tester.tap(tiles);
        await tester.pumpAndSettle();
        if (allowMultiple) {
          firstPhotoTrashed = true;
          await tester.tap(find.text('Add selected'));
          await _settleImages(tester);
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
          expect(
            find.widgetWithText(SelectionPreviewButton, '2'),
            findsOneWidget,
          );
        }
        await tester.tap(find.text('Add selected'));
        await _settleImages(tester);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
      const prefix = 'content://media/external/images/media/';
      expect(calls, [
        isMethodCall('setResult', arguments: {'uri': '${prefix}2'}),
        isMethodCall(
          'setResults',
          arguments: {
            'uris': ['${prefix}1', '${prefix}2'],
          },
        ),
      ]);
    },
  );

  testWidgets('editing can return an empty selection while closing cancels', (
    tester,
  ) async {
    for (final confirm in [true, false]) {
      await mount(
        tester,
        allowEmptySelection: true,
        initialSelection: library.items.take(1),
      );
      await tester.tap(find.byType(GalleryFileWidget).first);
      await tester.pumpAndSettle();
      if (confirm) {
        await tester.tap(find.text('Done'));
      } else {
        await tester.tap(find.byTooltip('Close'));
      }
      await _settleImages(tester);
      expect(await result, confirm ? isEmpty : isNull);
      expect(tester.takeException(), isNull);
    }
    await mount(tester);
    final button = tester.widget<ButtonComponent>(
      find.widgetWithText(ButtonComponent, 'Add selected'),
    );
    expect(button.isDisabled, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('uncapped selection previews and returns more than 50 items', (
    tester,
  ) async {
    final initial = library.items.take(100).toList();
    await mount(
      tester,
      selectionLimit: null,
      initialSelection: initial,
      size: const Size(500, 844),
      textScale: 3,
    );
    expect(find.widgetWithText(SelectionControlChip, '100'), findsOneWidget);
    final preview = find.byType(SelectionPreviewButton);
    final countBounds = tester.getRect(
      find.descendant(of: preview, matching: find.text('100')),
    );
    expect(
      countBounds.left,
      greaterThanOrEqualTo(tester.getRect(preview).left),
    );
    final file = fileFromAsset('', initial.last);
    FileLruCache.put('${file.tag}falsefalse', File('assets/memories.jpg'));
    await tester.tap(find.byTooltip('Preview'));
    await _settleImages(tester);
    expect(find.text('100 selected'), findsOneWidget);
    await tester.tap(find.text('Add selected'));
    await _settleImages(tester);
    expect(await result, initial);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('single selection replaces a preselected photo and returns it', (
    tester,
  ) async {
    await mount(
      tester,
      selectionLimit: 1,
      initialSelection: library.items.take(2),
    );
    expect(find.text('1/1'), findsOneWidget);
    await tester.tap(find.byType(GalleryFileWidget).at(1));
    await tester.pumpAndSettle();
    final file = fileFromAsset('', library.items[1]);
    FileLruCache.put('${file.tag}falsefalse', File('assets/memories.jpg'));
    await tester.tap(find.byTooltip('Preview'));
    await _settleImages(tester);
    expect(find.text('1/1 selected'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await _settleImages(tester);
    await tester.tap(find.text('Add selected'));
    await _settleImages(tester);
    expect(await result, [library.items[1]]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'limited-access notice scrolls so large text does not crowd out the gallery',
    (tester) async {
      library.access = PermissionState.limited;
      await mount(
        tester,
        size: const Size(844, 390),
        textScale: 3,
        locale: 'de',
      );
      expect(tester.takeException(), isNull);
      final strings = StringsLocalizations.of(
        tester.element(find.byType(DevicePickerPage)),
      );
      final notice = find.text(strings.devicePickerLimitedAccess);
      expect(notice.hitTestable(), findsOneWidget);
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      scroll.jumpTo(250);
      await _settleImages(tester);
      expect(notice.hitTestable(), findsNothing);
      await tester.tap(find.byType(GalleryFileWidget).hitTestable().first);
      await tester.pumpAndSettle();
      expect(find.text('1/50').hitTestable(), findsOneWidget);
      expect(find.text(strings.addSelected).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('device duration fills missing metadata for existing videos', (
    tester,
  ) async {
    final asset = AssetEntity(
      id: 'video',
      typeInt: 2,
      width: 1200,
      height: 800,
      duration: 65,
      title: 'video.mp4',
      createDateSecond: 1700000000,
    );
    library.items = [asset];
    library.knownFiles[asset.id] = fileFromAsset('Camera', asset)
      ..generatedID = 1
      ..duration = 0;
    await mount(tester);
    expect(find.text('1:05'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('gallery dates stay ordered when stored dates differ', (
    tester,
  ) async {
    library.items = library.items.take(3).toList();
    for (final (index, day) in [3, 1, 2].indexed) {
      final asset = library.items[index];
      library.knownFiles[asset.id] = fileFromAsset('Camera', asset)
        ..creationTime = DateTime(2026, 10, day).microsecondsSinceEpoch;
    }
    await mount(tester);
    expect(
      tester
          .widgetList<GalleryFileWidget>(find.byType(GalleryFileWidget))
          .map((tile) => tile.file.localID),
      ['0', '2', '1'],
    );
    library.knownFiles.clear();
    library.items = [
      for (final (index, asset) in library.items.indexed)
        asset.copyWith(
          createDateSecond:
              DateTime(2026, 10, index + 1).millisecondsSinceEpoch ~/ 1000,
        ),
    ];
    await tester
        .widget<DevicePickerGallery>(find.byType(DevicePickerGallery))
        .model
        .refresh();
    await _settleImages(tester);
    expect(
      tester
          .widgetList<GalleryFileWidget>(find.byType(GalleryFileWidget))
          .map((tile) => tile.file.localID),
      ['2', '1', '0'],
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('cleared local IDs still return the original device assets', (
    tester,
  ) async {
    final asset = library.items.first;
    final file = fileFromAsset('Camera', asset)..generatedID = 1;
    library.knownFiles[asset.id] = file;
    await mount(tester);
    file.localID = null;
    await tester.tap(find.byType(GalleryFileWidget).first);
    await tester.pumpAndSettle();
    expect(find.text('1/50'), findsOneWidget);
    await tester.tap(find.text('Add selected'));
    await _settleImages(tester);
    expect(await result, [asset]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Add selected in preview returns the remaining original assets', (
    tester,
  ) async {
    await mount(tester);
    final tiles = find.byType(GalleryFileWidget);
    for (final index in [1, 4, 7]) {
      final file = fileFromAsset('', library.items[index]);
      FileLruCache.put('${file.tag}falsefalse', File('assets/memories.jpg'));
      await tester.tap(tiles.at(index));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('Preview'));
    await _settleImages(tester);
    expect(find.text('3/50 selected'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(DetailPage))).brightness,
      Brightness.dark,
    );
    await tester.tapAt(tester.getCenter(find.byType(PageView)));
    await tester.pump(const Duration(milliseconds: 400));
    tester.widget<FileWidget>(find.byType(FileWidget).first).playbackCallback!(
      true,
      FullScreenRequestReason.playbackStateChange,
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove').hitTestable(), findsOneWidget);
    expect(find.text('Add selected').hitTestable(), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await _settleImages(tester);
    expect(find.byType(DevicePickerPage), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(DevicePickerPage))).brightness,
      Brightness.light,
    );
    await tester.tap(find.byTooltip('Preview'));
    await _settleImages(tester);
    expect(find.text('3/50 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove'));
    await _settleImages(tester);
    expect(find.text('2/50 selected'), findsOneWidget);
    await tester.tap(find.text('Add selected'));
    await _settleImages(tester);
    expect(find.byType(DetailPage), findsNothing);
    expect(find.byType(DevicePickerPage), findsNothing);
    expect(await result, [library.items[1], library.items[4]]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'missing assets in preview require reviewing the remaining selection',
    (tester) async {
      await mount(tester);
      final model = tester
          .widget<DevicePickerGallery>(find.byType(DevicePickerGallery))
          .model;
      model.replaceSelection(library.items.take(2));
      for (final asset in model.selection) {
        final file = fileFromAsset('', asset);
        FileLruCache.put('${file.tag}falsefalse', File('assets/memories.jpg'));
      }
      await _settleImages(tester);
      await tester.tap(find.byTooltip('Preview'));
      await _settleImages(tester);
      library.unavailable.add(library.items.first.id);
      await model.refresh();
      await _settleImages(tester);
      await tester.tap(find.text('Add selected'));
      await _settleImages(tester);
      expect(find.byType(DevicePickerPage), findsOneWidget);
      expect(find.text('1/50'), findsOneWidget);
      expect(
        find.text(
          "Some selected items couldn't be found. Check your selection and try again.",
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add selected'));
      await _settleImages(tester);
      expect(await result, [library.items[1]]);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'scrolling pages device assets without changing selection or gallery preferences',
    (tester) async {
      library.items = List.generate(10000, (i) => media('$i'));
      await mount(tester);
      final model = tester
          .widget<DevicePickerGallery>(find.byType(DevicePickerGallery))
          .model;
      expect(model.media.length, 96);
      await tester.tap(find.byType(GalleryFileWidget).first);
      await tester.pumpAndSettle();
      model.replaceSelection(
        library.items.take(50).map((item) => item.copyWith()),
      );
      await tester.pumpAndSettle();
      expect(library.fileLookupBatches, hasLength(1));
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await _settleImages(tester);
      expect(model.media.length, 192);
      expect(library.fileLookupBatches.expand((ids) => ids).length, 192);
      expect(model.selection, library.items.take(50));
      scroll.jumpTo(0);
      await _settleImages(tester);
      expect(library.fileLookupBatches.expand((ids) => ids).length, 192);
      expect(localSettings.getPhotoGridSize(), 5);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('closing during confirmation leaves the parent route open', (
    tester,
  ) async {
    await mount(tester, withParentRoute: true);
    await tester.tap(find.byType(GalleryFileWidget).first);
    await tester.pumpAndSettle();
    final pending = Completer<AssetEntity?>();
    library.resolveOverride = (_) => pending.future;
    await tester.tap(find.text('Add selected'));
    await tester.pump();
    navigatorKey.currentState!.pop();
    pending.complete(library.items.first);
    await _settleImages(tester);
    expect(await result, isNull);
    expect(find.text('Album'), findsOneWidget);
    expect(navigatorKey.currentState!.canPop(), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('stale gallery files do not occupy selection slots', (
    tester,
  ) async {
    await mount(tester);
    final tiles = find.byType(GalleryFileWidget);
    final first = tester.widget<GalleryFileWidget>(tiles.at(0));
    final second = tester.widget<GalleryFileWidget>(tiles.at(1));
    final model = tester
        .widget<DevicePickerGallery>(find.byType(DevicePickerGallery))
        .model;
    library.items.removeAt(0);
    await model.refresh();
    first.selectedFiles!.selectAll({first.file, second.file});
    expect(model.selection, [library.items.first]);
    expect(first.selectedFiles!.files, {second.file});
    await _settleImages(tester);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('device files remain selectable when metadata lookup fails', (
    tester,
  ) async {
    library.fileLookupError = StateError('Database unavailable');
    await mount(tester);
    await tester.tap(find.byType(GalleryFileWidget).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add selected'));
    await tester.pumpAndSettle();
    expect(await result, [library.items.first]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

Future<void> _settleImages(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  final context = tester.element(find.byType(Navigator).first);
  final providers = [
    ...tester
        .widgetList<Image>(find.byWidgetPredicate((widget) => widget is Image))
        .map((widget) => widget.image),
    ...tester
        .widgetList<ImageZoomViewer>(find.byType(ImageZoomViewer))
        .map((widget) => widget.imageProvider)
        .whereType<ImageProvider>(),
  ];
  await tester.runAsync(() async {
    var finished = false;
    final loading = Future.wait(
      providers.map((provider) => precacheImage(provider, context)),
    ).whenComplete(() => finished = true);
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!finished && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(finished, isTrue, reason: 'Fixture images should finish decoding');
    await loading;
  });
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}

Map<String, Object> _assetData(String id) => {
  'id': id,
  'type': 1,
  'width': 1200,
  'height': 800,
  'title': '$id.jpg',
  'createDt': 1700000000,
};

class _NoLocalDatabase extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async => null;
}

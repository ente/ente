import "dart:async";

import "package:dio/dio.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:photos/core/configuration.dart";
import "package:photos/events/collection_meta_event.dart";
import "package:photos/models/file/dummy_file.dart";
import "package:photos/models/file/file_sort_order.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/metadata/file_magic.dart";
import "package:photos/models/file_load_result.dart";
import "package:photos/models/gallery/gallery_groups.dart";
import "package:photos/service_locator.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/models/gallery/justified_layout_strategy.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/ui/viewer/gallery/component/group/type.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    ServiceLocator.instance.init(
      preferences,
      Dio(),
      Dio(),
      Dio(),
      PackageInfo(
        appName: "Photos",
        packageName: "photos",
        version: "1.0.0",
        buildNumber: "1",
      ),
    );

    // GalleryGroups only needs Configuration's preferences-backed user ID.
    // Plugin initialization is unavailable in a widget-test process.
    try {
      await Configuration.instance.init(preferences);
    } catch (_) {}

    // Construct the delayed flag refresher outside the widget-test fake clock.
    expect(flagService.internalUser, isTrue);
  });

  setUp(() async {
    await localSettings.setInternalUserDisabled(false);
    await localSettings.setGalleryLayoutType(GalleryLayoutType.grid);
    await localSettings.setJustifiedLayoutStrategy(
      JustifiedLayoutStrategy.comfortLarge,
    );
    await localSettings.resetFlexLayoutTuning();
    await localSettings.resetComfortLargeLayoutTuning();
  });

  tearDown(() async {
    await localSettings.setInternalUserDisabled(false);
  });

  testWidgets(
    "filename sorting loads the whole album and restores date grouping",
    (tester) async {
      var order = FileSortOrder.newestFirst;
      final events = StreamController<CollectionMetaEvent>.broadcast();
      addTearDown(events.close);
      final galleryKey = GlobalKey<GalleryState>();
      final limits = <int?>[];
      final files = List.generate(
        125,
        (index) => DummyFile(groupID: "sort", index: index)
          ..title = "photo${125 - index}.jpg"
          ..fileType = FileType.image
          ..pubMagicMetadata = PubMagicMetadata(w: 100, h: 100)
          ..uploadedFileID = index
          ..creationTime = DateTime(2026, 1, index + 1).microsecondsSinceEpoch,
      );
      await localSettings.setGalleryGroupType(GroupType.day);
      await tester.pumpWidget(
        MaterialApp(
          theme: lightThemeData,
          localizationsDelegates: StringsLocalizations.localizationsDelegates,
          supportedLocales: StringsLocalizations.supportedLocales,
          home: GalleryBoundariesProvider(
            child: GalleryFilesState(
              child: Gallery(
                key: galleryKey,
                tagPrefix: "album-sort",
                sortOrder: () => order,
                forceReloadEvents: [events.stream],
                reloadDebounceTime: Duration.zero,
                reloadDebounceExecutionInterval: Duration.zero,
                limitSelectionToOne: true,
                showSelectAll: false,
                asyncLoader: (start, end, {limit, asc}) async {
                  limits.add(limit);
                  final sorted = [...files]
                    ..sort(
                      (a, b) => asc == true
                          ? a.creationTime!.compareTo(b.creationTime!)
                          : b.creationTime!.compareTo(a.creationTime!),
                    );
                  return FileLoadResult(
                    sorted.take(limit ?? sorted.length).toList(),
                    limit != null,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(galleryKey.currentState!.galleryGroups!.groupType, GroupType.day);
      expect(limits, [100, null]);
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      position.jumpTo(400);
      await tester.pumpAndSettle();
      events.add(CollectionMetaEvent(1, CollectionMetaEventType.sortChanged));
      await tester.pumpAndSettle();
      expect(
        position.pixels,
        400,
        reason: "An unchanged sort preserves the scroll position",
      );

      for (final next in [
        FileSortOrder.filenameAscending,
        FileSortOrder.filenameDescending,
        FileSortOrder.oldestFirst,
        FileSortOrder.newestFirst,
      ]) {
        order = next;
        events.add(CollectionMetaEvent(1, CollectionMetaEventType.sortChanged));
        await tester.pumpAndSettle();
        final groups = galleryKey.currentState!.galleryGroups!;
        expect(groups.allFiles.length, 125);
        expect(position.pixels, 0);
        expect(
          groups.groupType,
          order.isFilename ? GroupType.none : GroupType.day,
        );
        expect(groups.allFiles.first.title, switch (order) {
          FileSortOrder.filenameAscending ||
          FileSortOrder.newestFirst => "photo1.jpg",
          _ => "photo125.jpg",
        });
        if (order.isFilename) {
          expect(groups.groupHeaderExtent, GalleryGroups.spacing);
          expect(groups.scrollbarDivisions, isEmpty);
          expect(limits.last, isNull);
          expect(
            groups.getOffsetOfGroupContainingFile(files[90]),
            groups.getOffsetOfFile(files[90]),
          );
        } else {
          expect(groups.groupHeaderExtent, greaterThan(GalleryGroups.spacing));
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}

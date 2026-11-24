import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photos/core/configuration.dart";
import "package:photos/db/ml/base.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/models/device_collection.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/search/device_album_search_result.dart";
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/models/search/hierarchical/hierarchical_search_filter.dart";
import "package:photos/models/search/search_constants.dart";
import "package:photos/models/search/search_result.dart";
import "package:photos/models/search/search_types.dart";
import "package:photos/module/metadata/local_file.dart";
import "package:photos/services/entity_service.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/ui/device_picker/device_picker_controller.dart";
import "package:photos/ui/picker/local_media_picker_search.dart";
import "package:photos/ui/viewer/search/search_suggestions.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../../device_picker/device_picker_test_helpers.dart";

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await Configuration.instance
        .init(preferences)
        .onError<MissingPluginException>((_, _) {});
    PersonService.init(_FakeEntityService(), _FakeMLDataDB(), preferences);
  });

  test('local picker restricts indexed results to accessible media', () async {
    final image = media('100');
    final video = media('101').copyWith(typeInt: 2);
    final fresh = media('103');
    final library = FakeDeviceLibrary()
      ..access = PermissionState.limited
      ..readOverride = (album, _, _) async {
        final filter = album.filterOption;
        if (filter is! CustomFilter) return [media('0')];
        expect(filter.makeOrderBy().single.column, CustomColumns.android.id);
        final where = filter.makeWhere();
        if (where.contains("lower('sam''s_%')")) return [fresh, image];
        if (where == '_id IN (104)') throw StateError('temporary read failure');
        final ids = RegExp(r'\d+').allMatches(where).map((m) => m[0]);
        return [video, image].where((asset) => ids.contains(asset.id)).toList();
      };
    library.folders[0] = library.folders.first.copyWith(
      type: RequestType.image,
    );
    final model = DevicePickerController(library: library);
    addTearDown(model.dispose);
    await model.refresh();
    final filename = (await searchLocalPickerAlbums(
      model,
      "sam's_%",
    )).whereType<PickerFilenameResult>().single;
    await model.openAlbum(filename.album, filenameMatches: true);
    await model.refresh();
    expect(model.media.map((asset) => asset.id), [fresh.id, image.id]);
    await model.openAlbum(model.albums.first);
    expect(model.media.single.id, '0');
    final indexed = [
      for (final asset in [media('102'), video, image])
        fileFromAsset('Camera', asset),
    ];
    final captureTime = DateTime.utc(2019).microsecondsSinceEpoch;
    indexed.last.creationTime = captureTime;
    applyMediaTypeMetadata(indexed.last, false, 42);
    final eligible = <String, EnteFile?>{};
    Future<void> resolve(List<EnteFile> files) =>
        resolveLocalSearchFiles(model, files, eligible, () => true);
    await resolve([fileFromAsset('Camera', media('104'))]);
    await resolve(indexed);
    expect(eligible.values.nonNulls.map((file) => file.localID), [image.id]);
    final match = eligible[image.id]!;
    expect(match.creationTime, captureTime);
    expect(match.pubMmdEncodedJson, indexed.last.pubMmdEncodedJson);
  });

  for (final theme in [lightThemeData, darkThemeData]) {
    testWidgets(
      "picker search groups keep selection callbacks in ${theme.brightness}",
      (tester) async {
        final normalOpened = <String>[];
        final results = <SearchResult>[
          DeviceAlbumSearchResult(
            DeviceCollection("screenshots", "Screenshots", count: 3),
          ),
          for (final (type, name) in [
            (ResultType.location, "Paris"),
            (ResultType.magic, "Holiday photos"),
            (ResultType.faces, "Alex"),
            (ResultType.month, "March"),
            (ResultType.fileCaption, "Birthday"),
            (ResultType.shared, "Sam shared"),
          ])
            GenericSearchResult(
              type,
              name,
              const [],
              hierarchicalSearchFilter: _FakeFilter(),
              onResultTap: (_) => normalOpened.add(name),
              params: type == ResultType.shared
                  ? {kContactUserId: 2, kContactEmail: "sam@example.com"}
                  : const {},
            ),
        ];
        final opened = <SearchResult>[];
        await tester.pumpWidget(
          _host(
            theme,
            ListView(
              children: [
                SearchResultsSectionsWidget(
                  query: "trip",
                  results: results,
                  resultBuilder: (result) => SearchResultsWidgetGenerator(
                    result,
                    onResultTap: () => opened.add(result),
                  ),
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        final sectionTops = [
          for (final title in [
            "Magic",
            "People",
            "Locations",
            "Moments",
            "Albums",
            "Shared",
            "Files",
          ])
            tester.getTopLeft(find.text(title).first).dy,
        ];
        for (var i = 1; i < sectionTops.length; i++) {
          expect(sectionTops[i], greaterThan(sectionTops[i - 1]));
        }
        expect(find.text("Device \u2022 3"), findsOneWidget);
        for (final result in results) {
          await tester.ensureVisible(find.text(result.name()));
          await tester.pumpAndSettle();
          await tester.tap(find.text(result.name()));
          await tester.pump(const Duration(seconds: 1));
        }
        expect(opened, results);
        final normalResult = results.whereType<GenericSearchResult>().first;
        await tester.pumpWidget(
          _host(theme, SearchResultsWidgetGenerator(normalResult)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(normalResult.name()));
        await tester.pump(const Duration(seconds: 1));
        expect(normalOpened, [normalResult.name()]);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Widget _host(ThemeData theme, Widget child) => MaterialApp(
  theme: theme,
  localizationsDelegates: StringsLocalizations.localizationsDelegates,
  supportedLocales: StringsLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

class _FakeEntityService extends Fake implements EntityService {}

class _FakeMLDataDB extends Fake implements IMLDataDB<int> {}

class _FakeFilter extends Fake implements HierarchicalSearchFilter {}

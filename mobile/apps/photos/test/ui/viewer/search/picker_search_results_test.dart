import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/core/configuration.dart";
import "package:photos/db/ml/base.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/models/device_collection.dart";
import "package:photos/models/search/device_album_search_result.dart";
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/models/search/hierarchical/hierarchical_search_filter.dart";
import "package:photos/models/search/search_constants.dart";
import "package:photos/models/search/search_result.dart";
import "package:photos/models/search/search_types.dart";
import "package:photos/services/entity_service.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/ui/viewer/search/search_suggestions.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await Configuration.instance
        .init(preferences)
        .onError<MissingPluginException>((_, _) {});
    PersonService.init(_FakeEntityService(), _FakeMLDataDB(), preferences);
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

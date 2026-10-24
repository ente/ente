import "dart:async";
import "dart:convert";
import "dart:typed_data";

import "package:dio/dio.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/machine_learning/face_ml/feedback/cluster_feedback.dart";
import "package:photos/ui/viewer/people/file_face_widget.dart";
import "package:photos/ui/viewer/people/person_cluster_suggestion.dart";
import "package:photos/ui/viewer/people/person_gallery_suggestion.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({"remote_flags": "{}"});
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response(
              requestOptions: options,
              data: <String, dynamic>{},
              statusCode: 200,
            ),
          ),
        ),
      );
    ServiceLocator.instance.init(
      await SharedPreferences.getInstance(),
      dio,
      dio,
      dio,
      PackageInfo(
        appName: "Photos",
        packageName: "photos",
        version: "1",
        buildNumber: "1",
      ),
    );
  });

  for (final standalone in [false, true]) {
    testWidgets(
      "background People card refreshes an unscoped split from ${standalone ? 'review' : 'person'} preview",
      (tester) async {
        final fixture = _Fixture();
        await fixture.mount(tester, false, allPeople: true);
        final navigator = Navigator.of(
          tester.element(find.byType(PersonGallerySuggestion)),
        );
        unawaited(
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => standalone
                  ? fixture.review(true)
                  : Scaffold(body: fixture.review(false)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            ValueKey(standalone ? "cluster_id-first-files-1" : "suggestion_0"),
          ),
        );
        await tester.pump();
        fixture.suggestions = [fixture.suggestion("split", 2)];
        // ClusterAppBar does not include a cluster/person ID in this event.
        Bus.instance.fire(PeopleChangedEvent());
        await tester.pumpAndSettle();
        expect(
          fixture.loads,
          3,
          reason: "refresh the background card, defer the preview",
        );
        expect(fixture.clusters(tester).single, "split");
        fixture.preview.complete(null);
        await tester.pumpAndSettle();
        expect(fixture.loads, 4);
        navigator.pop();
        await tester.pumpAndSettle();
        expect(fixture.clusters(tester).single, "split");
        expect(fixture.thumbnails(tester).map((w) => w.file.uploadedFileID), [
          2,
        ]);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final standalone in [false, true]) {
    for (final groupEdit in [false, true]) {
      testWidgets(
        "canceling the naming form applies a deferred ${groupEdit ? 'group' : 'file'} change ($standalone)",
        (tester) async {
          final fixture = _Fixture();
          await fixture.mount(tester, standalone);
          await tester.tap(find.text("Save as another person"));
          await tester.pump();
          fixture.suggestions = [];
          Bus.instance.fire(
            groupEdit
                ? PeopleChangedEvent(
                    source: "first",
                    type: PeopleEventType.removedFilesFromCluster,
                  )
                : FilesUpdatedEvent([
                    EnteFile()..uploadedFileID = 1,
                  ], type: EventType.hide),
          );
          await tester.pump();
          expect(fixture.loads, 1);
          fixture.preview.complete(false);
          await tester.pumpAndSettle();
          expect(fixture.loads, 2);
          expect(fixture.clusters(tester), isEmpty);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
    for (final initial in [false, true]) {
      for (final groupEdit in [false, true]) {
        testWidgets(
          "pending query handles ${groupEdit ? 'group' : 'file'} changes ($standalone, initial: $initial)",
          (tester) async {
            final fixture = _Fixture();
            final captured = List<ClusterSuggestion>.of(fixture.suggestions);
            final pending = Completer<List<ClusterSuggestion>>();
            if (initial) fixture.loadOverride = () => pending.future;
            await fixture.mount(tester, standalone, settle: !initial);
            if (!initial) {
              fixture.loadOverride = () => pending.future;
              fixture.reviewed();
              await tester.pump();
            }
            fixture.loadOverride = null;
            fixture.suggestions = [];
            Bus.instance.fire(
              groupEdit
                  ? PeopleChangedEvent(
                      source: "first",
                      type: PeopleEventType.removedFaceFromCluster,
                    )
                  : FilesUpdatedEvent(
                      [EnteFile()..uploadedFileID = 1],
                      type: initial
                          ? EventType.deletedFromEverywhere
                          : EventType.hide,
                    ),
            );
            await tester.pump();
            pending.complete(captured);
            await tester.pumpAndSettle();
            expect(fixture.clusters(tester), isEmpty);
            expect(fixture.loads, initial ? 2 : 3);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }

  for (final standalone in [false, true]) {
    final surface = standalone ? "review page" : "person card";

    testWidgets("$surface refreshes deleted candidates by uploaded ID", (
      tester,
    ) async {
      final fixture = _Fixture();
      await fixture.mount(tester, standalone);
      fixture.suggestions = [];
      Bus.instance.fire(
        FilesUpdatedEvent([
          EnteFile()
            ..uploadedFileID = 1
            ..generatedID = 999,
        ], type: EventType.deletedFromEverywhere),
      );
      await tester.pumpAndSettle();
      expect(fixture.loads, 2);
      expect(fixture.clusters(tester), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets("$surface defers preview edits then requeries membership", (
      tester,
    ) async {
      final fixture = _Fixture();
      await fixture.mount(tester, standalone);
      if (standalone) {
        await tester.tap(
          find.byKey(const ValueKey("cluster_id-first-files-1")),
        );
      } else {
        await tester.tap(find.byKey(const ValueKey("suggestion_0")));
      }
      await tester.pump();
      fixture.suggestions = [fixture.suggestion("split", 2)];
      Bus.instance.fire(
        PeopleChangedEvent(
          source: "first",
          type: PeopleEventType.removedFilesFromCluster,
          relevantFiles: [EnteFile()..uploadedFileID = 1],
        ),
      );
      Bus.instance.fire(PeopleChangedEvent());
      await tester.pump();
      expect(
        fixture.loads,
        1,
        reason: "coalesce edits until the preview closes",
      );
      fixture.preview.complete(null);
      await tester.pumpAndSettle();
      expect(fixture.loads, 2);
      expect(fixture.clusters(tester).single, "split");
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets("$surface cannot restore a deleted candidate from late crops", (
      tester,
    ) async {
      final fixture = _Fixture();
      final crops = Completer<void>();
      fixture.beforeCrops = () => crops.future;
      await fixture.mount(tester, standalone, settle: false);
      await tester.pump();
      fixture.suggestions = [];
      Bus.instance.fire(
        FilesUpdatedEvent([
          EnteFile()..uploadedFileID = 1,
        ], type: EventType.hide),
      );
      await tester.pumpAndSettle();
      crops.complete();
      await tester.pumpAndSettle();
      expect(fixture.clusters(tester), isEmpty);
      expect(fixture.loads, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets("$surface refreshes only its reviewed person", (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester, standalone);
      Bus.instance.fire(
        PeopleChangedEvent(
          type: PeopleEventType.reviewedSuggestion,
          person: PersonEntity("other", PersonData(name: "Other")),
        ),
      );
      await tester.pumpAndSettle();
      expect(fixture.loads, 1);
      fixture.suggestions = [];
      fixture.reviewed();
      await tester.pumpAndSettle();
      expect(fixture.loads, 2);
      expect(fixture.clusters(tester), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets("$surface waits for saving before applying invalidation", (
      tester,
    ) async {
      final fixture = _Fixture();
      await fixture.mount(tester, standalone);
      await tester.tap(find.text("Yes"));
      await tester.pump();
      fixture.suggestions = [];
      Bus.instance.fire(
        FilesUpdatedEvent([
          EnteFile()..uploadedFileID = 1,
        ], type: EventType.deletedFromRemote),
      );
      await tester.pump();
      expect(fixture.loads, 1);
      fixture.save.complete();
      await tester.pumpAndSettle();
      expect(fixture.loads, 2);
      expect(fixture.clusters(tester), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets("$surface keeps the sender's next candidate after feedback", (
      tester,
    ) async {
      final fixture = _Fixture();
      fixture.suggestions.add(fixture.suggestion("second", 2));
      await fixture.mount(tester, standalone);
      await tester.tap(find.text("Yes"));
      fixture.save.complete();
      await tester.pumpAndSettle();
      expect(
        fixture.loads,
        1,
        reason: "do not invalidate the sender's preview",
      );
      expect(fixture.clusters(tester), ["second"]);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets("late query cannot change the displayed candidate's person", (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.mount(tester, false, allPeople: true);
    final previous = List<ClusterSuggestion>.of(fixture.suggestions);
    final stale = Completer<List<ClusterSuggestion>>();
    fixture.loadOverride = () => stale.future;
    fixture.reviewed();
    await tester.pump();
    fixture.loadOverride = null;
    final other = PersonEntity("other", PersonData(name: "Other"));
    fixture.suggestions = [
      ClusterSuggestion(
        other,
        "second",
        0.1,
        false,
        fixture.suggestion("second", 2).filesInCluster,
        [],
      ),
    ];
    fixture.reviewed();
    await tester.pumpAndSettle();
    stale.complete(previous);
    await tester.pumpAndSettle();
    // Rebuild the retained card as a parent update would; its visible name
    // must still describe the new candidate, not the obsolete query result.
    await fixture.mount(tester, false, allPeople: true);
    expect(fixture.clusters(tester), ["second"]);
    expect(find.text("Other"), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final standalone in [false, true]) {
    for (final accepted in [false, true]) {
      for (final leaveBeforeSave in [false, true]) {
        testWidgets(
          "all-people card refreshes after ${standalone ? 'review' : 'person'} page feedback ($accepted, early return: $leaveBeforeSave)",
          (tester) async {
            final fixture = _Fixture();
            await fixture.mount(tester, false, allPeople: true);
            final navigator = Navigator.of(
              tester.element(find.byType(PersonGallerySuggestion)),
            );
            unawaited(
              navigator.push(
                MaterialPageRoute<void>(
                  builder: (_) => standalone
                      ? fixture.review(true)
                      : Scaffold(body: fixture.review(false)),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text(accepted ? "Yes" : "No"));
            await tester.pump();
            await tester.pump(const Duration(seconds: 1));
            fixture.suggestions = [];
            if (leaveBeforeSave) {
              navigator.pop();
              await tester.pumpAndSettle();
            }
            fixture.save.complete();
            await tester.pumpAndSettle();
            if (!leaveBeforeSave) {
              navigator.pop();
              await tester.pumpAndSettle();
            }
            expect(fixture.clusters(tester), isEmpty);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }

  testWidgets("naming a review group cannot retain a newly deleted candidate", (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.mount(tester, true);
    await tester.tap(find.text("Save as another person"));
    await tester.pump();
    final pending = Completer<List<ClusterSuggestion>>();
    fixture.loadOverride = () => pending.future;
    fixture.preview.complete(true);
    await tester.pump();
    fixture.loadOverride = null;
    fixture.suggestions = [];
    Bus.instance.fire(
      FilesUpdatedEvent([
        EnteFile()..uploadedFileID = 99,
      ], type: EventType.hide),
    );
    await tester.pump();
    pending.complete([fixture.suggestion("new", 99)]);
    await tester.pumpAndSettle();
    expect(fixture.loads, 3);
    expect(fixture.clusters(tester), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets("all-people card ignores an obsolete suggestion query", (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.mount(tester, false, allPeople: true);
    final previous = List<ClusterSuggestion>.of(fixture.suggestions);
    final stale = Completer<List<ClusterSuggestion>>();
    fixture.loadOverride = () => stale.future;
    fixture.reviewed();
    await tester.pump();
    fixture.loadOverride = null;
    fixture.suggestions = [];
    fixture.reviewed();
    await tester.pumpAndSettle();
    stale.complete(previous);
    await tester.pumpAndSettle();
    expect(fixture.loads, 3);
    expect(fixture.clusters(tester), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _Fixture {
  _Fixture() {
    suggestions = [suggestion("first", 1)];
  }
  final person = PersonEntity("person", PersonData(name: "Alex"));
  final save = Completer<void>();
  final preview = Completer<Object?>();
  final rootKey = UniqueKey();
  late List<ClusterSuggestion> suggestions;
  int loads = 0;
  Future<List<ClusterSuggestion>> Function()? loadOverride;
  Future<void> Function()? beforeCrops;
  final pixel = base64Decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQI12P4z8DwHwAFAAH/cpxSZwAAAABJRU5ErkJggg==",
  );

  ClusterSuggestion suggestion(String cluster, int id) =>
      ClusterSuggestion(person, cluster, 0.1, false, [
        EnteFile()
          ..uploadedFileID = id
          ..creationTime = id
          ..fileType = FileType.image
          ..title = "fixture.jpg",
      ], []);
  Future<List<ClusterSuggestion>> load() async {
    loads++;
    return loadOverride?.call() ?? List.of(suggestions);
  }

  Future<Map<int, Uint8List?>> crops(
    List<EnteFile> files,
    String cluster,
  ) async {
    await beforeCrops?.call();
    return {for (final file in files) file.uploadedFileID!: pixel};
  }

  void reviewed() => Bus.instance.fire(
    PeopleChangedEvent(
      type: PeopleEventType.reviewedSuggestion,
      person: person,
    ),
  );
  Iterable<FileFaceWidget> thumbnails(WidgetTester tester) =>
      tester.widgetList<FileFaceWidget>(
        find.descendant(
          of: find.byKey(rootKey, skipOffstage: false),
          matching: find.byType(FileFaceWidget, skipOffstage: false),
          skipOffstage: false,
        ),
      );
  List<String?> clusters(WidgetTester tester) =>
      thumbnails(tester).map((w) => w.clusterID).toSet().toList();

  Widget review(bool standalone, {bool allPeople = false, Key? key}) =>
      standalone
      ? PersonReviewClusterSuggestion(
          person,
          key: key,
          loadSuggestions: load,
          saveFeedback: (_, _) => save.future,
          generateFaceThumbnails: crops,
          openPage: (_) => preview.future,
        )
      : PersonGallerySuggestion(
          person: allPeople ? null : person,
          key: key,
          loadSuggestions: load,
          saveFeedback: (_, _) => save.future,
          generateFaceThumbnails: crops,
          openPage: (_) => preview.future,
        );
  Future<void> mount(
    WidgetTester tester,
    bool standalone, {
    bool allPeople = false,
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(420, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final widget = review(standalone, allPeople: allPeople, key: rootKey);
    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: StringsLocalizations.supportedLocales,
        home: standalone
            ? widget
            : Scaffold(
                appBar: AppBar(title: const Text("People")),
                body: widget,
              ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    }
  }
}

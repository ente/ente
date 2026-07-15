import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/sync_status_update_event.dart";
import "package:photos/generated/intl/app_localizations.dart";
import "package:photos/models/file_load_result.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/viewer/gallery/empty_state.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/sync_aware_empty_state.dart";

void main() {
  final l10n = lookupAppLocalizations(const Locale("en"));

  Widget testApp({required bool Function() isSyncInProgress, Widget? child}) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SyncAwareEmptyState(
        isSyncInProgress: isSyncInProgress,
        child: child ?? const EmptyState(),
      ),
    );
  }

  test("Gallery uses the sync-aware empty state by default", () {
    final gallery = Gallery(
      asyncLoader: (_, _, {limit, asc}) async => FileLoadResult([], false),
      tagPrefix: "test_gallery",
    );

    expect(gallery.emptyState, isA<SyncAwareEmptyState>());
  });

  testWidgets("shows syncing row only while sync is active", (tester) async {
    var isSyncInProgress = false;
    await tester.pumpWidget(testApp(isSyncInProgress: () => isSyncInProgress));

    expect(find.text(l10n.nothingToSeeHere), findsOneWidget);
    expect(find.text(l10n.syncing), findsNothing);
    expect(find.byType(EnteLoadingWidget), findsNothing);

    isSyncInProgress = true;
    Bus.instance.fire(SyncStatusUpdate(SyncStatus.applyingRemoteDiff));
    await tester.pump(Duration.zero);

    expect(find.text(l10n.nothingToSeeHere), findsNothing);
    expect(find.text(l10n.syncing), findsOneWidget);
    expect(find.byType(EnteLoadingWidget), findsOneWidget);

    isSyncInProgress = false;
    Bus.instance.fire(SyncStatusUpdate(SyncStatus.completedBackup));
    await tester.pump(Duration.zero);

    expect(find.text(l10n.nothingToSeeHere), findsOneWidget);
    expect(find.text(l10n.syncing), findsNothing);
    expect(find.byType(EnteLoadingWidget), findsNothing);
  });

  testWidgets("reads active sync state on first build", (tester) async {
    await tester.pumpWidget(testApp(isSyncInProgress: () => true));

    expect(find.text(l10n.syncing), findsOneWidget);
    expect(find.byType(EnteLoadingWidget), findsOneWidget);
  });

  testWidgets("rechecks an active sync without a terminal event", (
    tester,
  ) async {
    var isSyncInProgress = true;
    await tester.pumpWidget(testApp(isSyncInProgress: () => isSyncInProgress));
    expect(find.text(l10n.syncing), findsOneWidget);

    isSyncInProgress = false;
    await tester.pump(SyncAwareEmptyState.recheckInterval);

    expect(find.text(l10n.nothingToSeeHere), findsOneWidget);
    expect(find.text(l10n.syncing), findsNothing);
  });

  testWidgets("rechecks an idle gallery when sync starts quietly", (
    tester,
  ) async {
    var isSyncInProgress = false;
    await tester.pumpWidget(testApp(isSyncInProgress: () => isSyncInProgress));
    expect(find.text(l10n.nothingToSeeHere), findsOneWidget);

    isSyncInProgress = true;
    await tester.pump(SyncAwareEmptyState.recheckInterval);

    expect(find.text(l10n.syncing), findsOneWidget);
    expect(find.byType(EnteLoadingWidget), findsOneWidget);
  });

  testWidgets("preserves a custom empty state while idle", (tester) async {
    const customEmptyState = Text("Custom empty state");
    await tester.pumpWidget(
      testApp(isSyncInProgress: () => false, child: customEmptyState),
    );

    expect(find.byWidget(customEmptyState), findsOneWidget);
    expect(find.text(l10n.syncing), findsNothing);
  });

  testWidgets("fits narrow screens at large accessibility text sizes", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale("de"),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(3)),
            child: SyncAwareEmptyState(isSyncInProgress: () => true),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}

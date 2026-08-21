import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:photos/ente_theme_data.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/ui/sharing/library_sharing/library_sharing_controller.dart';
import 'package:photos/ui/sharing/library_sharing/library_sharing_page.dart';
import 'package:photos/ui/sharing/library_sharing/library_sharing_selection_sheet.dart';
import 'package:photos/ui/sharing/library_sharing/library_sharing_sheets.dart';

import 'library_sharing_test_helpers.dart';

void main() {
  testWidgets('offers to review albums that were previously unshared', (
    tester,
  ) async {
    final repository = FakeLibrarySharingRepository([
      librarySharingTestAlbum(1),
      librarySharingTestAlbum(2),
    ])..automaticSharingBlockedIDs.add(2);
    final controller = _LayoutTestLibrarySharingController(repository);

    await tester.pumpWidget(
      _app(
        LibrarySharingPage(
          recipient: librarySharingTestRecipient,
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Library sharing'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Enable'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text("1 album wasn't shared"), findsOneWidget);
    expect(
      find.text(
        "Sharing was stopped for this album earlier, so it wasn't shared again.",
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(controller.isAddingAlbums, isTrue);
    expect(find.text('Share with'), findsOneWidget);
  });

  testWidgets('mixed selection routes role editing and offers stop sharing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeLibrarySharingRepository([
      librarySharingTestAlbum(
        1,
        recipientRole: CollectionParticipantRole.viewer,
      ),
      librarySharingTestAlbum(
        2,
        recipientRole: CollectionParticipantRole.admin,
      ),
    ]);
    final controller = LibrarySharingController(
      recipient: librarySharingTestRecipient,
      repository: repository,
    );
    await controller.load();
    controller.enterManageMode();
    controller.selectAll();
    var mixedRolesOpened = false;

    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: LibrarySharingSelectionSheet(
              controller: controller,
              onApply: () async {},
              onStopSharing: () async {},
              onShowMixedRoles: () => mixedRolesOpened = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 selected'), findsOneWidget);
    expect(find.text('Mixed'), findsOneWidget);
    expect(find.text('Stop sharing'), findsOneWidget);

    await tester.tap(find.text('Mixed'));
    expect(mixedRolesOpened, isTrue);
  });

  testWidgets('roles sheet cannot be dismissed while an update is running', (
    tester,
  ) async {
    final gate = Completer<void>();
    final repository =
        FakeLibrarySharingRepository([
            librarySharingTestAlbum(
              1,
              recipientRole: CollectionParticipantRole.viewer,
            ),
            librarySharingTestAlbum(
              2,
              recipientRole: CollectionParticipantRole.admin,
            ),
          ])
          ..shareGate = gate
          ..shareFailures[1] = StateError('failed');
    final controller = LibrarySharingController(
      recipient: librarySharingTestRecipient,
      repository: repository,
    );
    await controller.load();
    controller.enterManageMode();
    controller.selectAll();
    controller.setRoleForAlbum(1, CollectionParticipantRole.collaborator);
    bool? result;

    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showLibrarySharingRolesSheet(
                  context: context,
                  controller: controller,
                  albumThumbnailBuilder: (_, _) =>
                      const ColoredBox(color: Colors.red),
                );
              },
              child: const Text('Open roles'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open roles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update roles'));
    await tester.pump();

    expect(controller.isMutating, isTrue);
    expect(find.byTooltip('Close'), findsNothing);
    await tester.tapAt(const Offset(8, 8));
    await tester.pump();
    expect(find.text('Roles'), findsOneWidget);
    await tester.drag(find.byType(BottomSheet), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(find.text('Roles'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(find.text('Roles'), findsNothing);
  });

  testWidgets('supports sheet expansion controls over scrollable content', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _LayoutTestLibrarySharingController();
    await controller.load();
    controller.enterManageMode();
    controller.selectAll();

    await tester.pumpWidget(
      _app(
        LibrarySharingPage(
          recipient: librarySharingTestRecipient,
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollView = find.byType(CustomScrollView);
    final selectionSheet = find.byType(LibrarySharingSelectionSheet);
    final selectionSheetAnimation = find.ancestor(
      of: selectionSheet,
      matching: find.byType(AnimatedSize),
    );
    expect(scrollView, findsOneWidget);
    expect(selectionSheet, findsOneWidget);
    expect(selectionSheetAnimation, findsOneWidget);
    bool isExpanded() =>
        tester.widget<LibrarySharingSelectionSheet>(selectionSheet).isExpanded;
    expect(isExpanded(), isTrue);
    final expandedHeight = tester.getSize(selectionSheet).height;
    expect(
      tester.getBottomLeft(scrollView).dy,
      greaterThan(tester.getTopLeft(selectionSheet).dy),
    );

    await tester.drag(selectionSheet, const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(isExpanded(), isFalse);
    expect(find.text('Role'), findsNothing);
    expect(find.text('Stop sharing'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);

    await tester.drag(selectionSheet, const Offset(0, -100));
    await tester.pump();
    expect(isExpanded(), isTrue);
    expect(tester.getSize(selectionSheet).height, expandedHeight);
    expect(
      tester.getSize(selectionSheetAnimation).height,
      lessThan(expandedHeight),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(tester.getCenter(selectionSheet));
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    expect(isExpanded(), isTrue);
    await gesture.moveBy(const Offset(0, -10));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(isExpanded(), isFalse);

    await tester.drag(selectionSheet, const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(isExpanded(), isTrue);

    final scrollContext = tester.element(scrollView);
    final scrollPosition = tester
        .state<ScrollableState>(
          find.descendant(of: scrollView, matching: find.byType(Scrollable)),
        )
        .position;
    ScrollUpdateNotification(
      metrics: scrollPosition,
      context: scrollContext,
      scrollDelta: 16,
      dragDetails: DragUpdateDetails(globalPosition: Offset.zero),
    ).dispatch(scrollContext);
    await tester.pumpAndSettle();
    expect(isExpanded(), isFalse);

    ScrollUpdateNotification(
      metrics: scrollPosition,
      context: scrollContext,
      scrollDelta: 16,
      dragDetails: DragUpdateDetails(globalPosition: Offset.zero),
    ).dispatch(scrollContext);
    await tester.pumpAndSettle();
    expect(isExpanded(), isFalse);

    ScrollUpdateNotification(
      metrics: scrollPosition,
      context: scrollContext,
      scrollDelta: -16,
      dragDetails: DragUpdateDetails(globalPosition: Offset.zero),
    ).dispatch(scrollContext);
    await tester.pumpAndSettle();
    expect(isExpanded(), isFalse);

    ScrollUpdateNotification(
      metrics: scrollPosition,
      context: scrollContext,
      scrollDelta: -16,
      dragDetails: DragUpdateDetails(globalPosition: Offset.zero),
    ).dispatch(scrollContext);
    await tester.pumpAndSettle();
    expect(isExpanded(), isTrue);

    final semantics = tester.ensureSemantics();
    final selectionControls = find.bySemanticsLabel('Album selection controls');
    var semanticsData = tester
        .getSemantics(selectionControls)
        .getSemanticsData();
    expect(semanticsData.flagsCollection.isExpanded, Tristate.isTrue);
    expect(semanticsData.hasAction(SemanticsAction.collapse), isTrue);
    expect(semanticsData.hasAction(SemanticsAction.expand), isFalse);

    final semanticsNode = tester.getSemantics(selectionControls);
    semanticsNode.owner!.performAction(
      semanticsNode.id,
      SemanticsAction.collapse,
    );
    await tester.pumpAndSettle();
    expect(isExpanded(), isFalse);
    semanticsData = tester.getSemantics(selectionControls).getSemanticsData();
    expect(semanticsData.flagsCollection.isExpanded, Tristate.isFalse);
    expect(semanticsData.hasAction(SemanticsAction.expand), isTrue);
    expect(semanticsData.hasAction(SemanticsAction.collapse), isFalse);
    semantics.dispose();
  });

  testWidgets('fits 2x accessibility text on a 320x568 viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _LayoutTestLibrarySharingController();
    await controller.load();
    controller.enterManageMode();
    controller.selectAll();

    await tester.pumpWidget(
      _app(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(2),
          ),
          child: LibrarySharingPage(
            recipient: librarySharingTestRecipient,
            controller: controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LibrarySharingSelectionSheet), findsOneWidget);
    expect(find.text('Role'), findsOneWidget);
    expect(find.text('Stop sharing'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the role action reachable for long selections', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeLibrarySharingRepository([
      for (var index = 0; index < 16; index++)
        librarySharingTestAlbum(
          index + 1,
          recipientRole: index.isEven
              ? CollectionParticipantRole.viewer
              : CollectionParticipantRole.admin,
        ),
    ]);
    final controller = LibrarySharingController(
      recipient: librarySharingTestRecipient,
      repository: repository,
    );
    await controller.load();
    controller.enterManageMode();
    controller.selectAll();

    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showLibrarySharingRolesSheet(
                context: context,
                controller: controller,
                albumThumbnailBuilder: (_, album) => ColoredBox(
                  key: ValueKey('album-thumbnail-${album.id}'),
                  color: Colors.red,
                ),
              ),
              child: const Text('Open roles'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open roles'));
    await tester.pumpAndSettle();

    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(find.byKey(const ValueKey('album-thumbnail-1')), findsOneWidget);
    final roleList = find.byKey(const ValueKey('library-sharing-role-list'));
    expect(find.text('Update roles'), findsOneWidget);
    for (var index = 0; index < 6; index++) {
      await tester.drag(roleList, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey('album-thumbnail-16')), findsOneWidget);
    expect(find.text('Update roles'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _app(Widget home) {
  return MaterialApp(
    theme: lightThemeData,
    localizationsDelegates: StringsLocalizations.localizationsDelegates,
    supportedLocales: StringsLocalizations.supportedLocales,
    home: home,
  );
}

class _LayoutTestLibrarySharingController extends LibrarySharingController {
  _LayoutTestLibrarySharingController([
    FakeLibrarySharingRepository? repository,
  ]) : super(
         recipient: librarySharingTestRecipient,
         repository:
             repository ??
             FakeLibrarySharingRepository([
               librarySharingTestAlbum(
                 1,
                 recipientRole: CollectionParticipantRole.viewer,
               ),
             ]),
       );

  @override
  List<Collection> get visibleAlbums => const [];
}

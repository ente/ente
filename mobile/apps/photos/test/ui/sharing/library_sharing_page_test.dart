import 'dart:async';

import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photos/ente_theme_data.dart';
import 'package:photos/generated/l10n.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/ui/sharing/library_sharing/library_sharing_controller.dart';
import 'package:photos/ui/sharing/library_sharing/library_sharing_page.dart';
import 'package:photos/ui/sharing/library_sharing/library_sharing_selection_sheet.dart';
import 'package:photos/ui/sharing/library_sharing/library_sharing_sheets.dart';

import 'library_sharing_test_helpers.dart';

void main() {
  testWidgets('empty first-time flow hides unavailable selection controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = LibrarySharingController(
      recipient: librarySharingTestRecipient,
      repository: FakeLibrarySharingRepository(const []),
    );

    await tester.pumpWidget(
      _app(
        LibrarySharingPage(
          recipient: librarySharingTestRecipient,
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LibrarySharingSelectionSheet), findsNothing);
    expect(find.text('No albums to share yet'), findsOneWidget);
    expect(find.byType(ToggleSwitchComponent), findsNothing);
  });

  testWidgets('existing recipient add mode renders the Share with state', (
    tester,
  ) async {
    final controller = LibrarySharingController(
      recipient: librarySharingTestRecipient,
      repository: FakeLibrarySharingRepository([
        librarySharingTestAlbum(
          1,
          recipientRole: CollectionParticipantRole.viewer,
        ),
      ]),
    );
    await controller.load();
    controller.enterAddMode();

    await tester.pumpWidget(
      _app(
        LibrarySharingPage(
          recipient: librarySharingTestRecipient,
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Share with'), findsOneWidget);
    expect(find.text('Sharing with'), findsNothing);
    expect(find.text('You are sharing your full library!'), findsOneWidget);
    expect(find.byType(LibrarySharingSelectionSheet), findsNothing);
    expect(find.byType(ToggleSwitchComponent), findsNothing);
  });

  testWidgets('library sharing banner opens the enable preview', (
    tester,
  ) async {
    final controller = _LayoutTestLibrarySharingController();

    await tester.pumpWidget(
      _app(
        LibrarySharingPage(
          recipient: librarySharingTestRecipient,
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Library Sharing'), findsOneWidget);
    expect(find.text('Share all your albums'), findsOneWidget);
    final toggle = tester.widget<ToggleSwitchComponent>(
      find.byKey(const ValueKey('library-sharing-toggle')),
    );
    expect(toggle.selected, isFalse);

    await tester.tap(find.byKey(const ValueKey('library-sharing-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('Enable library sharing?'), findsOneWidget);
    expect(
      find.text(
        'Your existing albums, and the ones you create in the future will be automatically shared with Friend.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Hidden albums will not be shared. You can stop sharing any album at any time.',
      ),
      findsOneWidget,
    );
    expect(find.text('Role'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);

    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();

    expect(find.text('Enable library sharing?'), findsNothing);
    expect(find.text('Coming soon'), findsOneWidget);
    expect(
      tester
          .widget<ToggleSwitchComponent>(
            find.byKey(const ValueKey('library-sharing-toggle')),
          )
          .selected,
      isFalse,
    );
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('shows selection controls only after selecting an album', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _LayoutTestLibrarySharingController(isShared: false);

    await tester.pumpWidget(
      _app(
        LibrarySharingPage(
          recipient: librarySharingTestRecipient,
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Share with'), findsOneWidget);
    expect(find.byType(LibrarySharingSelectionSheet), findsNothing);

    controller.selectAll();
    await tester.pumpAndSettle();
    expect(find.byType(LibrarySharingSelectionSheet), findsOneWidget);

    controller.clearSelection();
    await tester.pumpAndSettle();
    expect(find.byType(LibrarySharingSelectionSheet), findsNothing);
  });

  testWidgets('hides the library sharing banner while albums are selected', (
    tester,
  ) async {
    final controller = _LayoutTestLibrarySharingController();

    await tester.pumpWidget(
      _app(
        LibrarySharingPage(
          recipient: librarySharingTestRecipient,
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Library Sharing'), findsOneWidget);
    expect(find.byType(LibrarySharingSelectionSheet), findsNothing);

    controller.enterManageMode();
    controller.selectAll();
    await tester.pumpAndSettle();
    expect(find.text('Library Sharing'), findsNothing);
    expect(find.byType(LibrarySharingSelectionSheet), findsOneWidget);

    controller.clearSelection();
    await tester.pumpAndSettle();
    expect(find.text('Library Sharing'), findsOneWidget);
    expect(find.byType(LibrarySharingSelectionSheet), findsNothing);
    expect(find.byTooltip('Share albums'), findsOneWidget);
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

  testWidgets('shows loading before the empty add state', (tester) async {
    final loadGate = Completer<List<Collection>>();
    final controller = LibrarySharingController(
      recipient: librarySharingTestRecipient,
      repository: FakeLibrarySharingRepository(const [], loadGate: loadGate),
    );

    await tester.pumpWidget(
      _app(
        LibrarySharingPage(
          recipient: librarySharingTestRecipient,
          controller: controller,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(LibrarySharingSelectionSheet), findsNothing);

    loadGate.complete(const []);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No albums to share yet'), findsOneWidget);
    expect(find.byType(LibrarySharingSelectionSheet), findsNothing);
  });

  testWidgets('all-selected state clears through the selected-count chip', (
    tester,
  ) async {
    final controller = LibrarySharingController(
      recipient: librarySharingTestRecipient,
      repository: FakeLibrarySharingRepository([
        librarySharingTestAlbum(1),
        librarySharingTestAlbum(2),
      ]),
    );
    await controller.load();
    controller.selectAll();

    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => LibrarySharingSelectionSheet(
                controller: controller,
                onApply: () async {},
                onStopSharing: () async {},
                onShowMixedRoles: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final selectAll = tester.widget<SelectionSummaryChipComponent>(
      find.byKey(const ValueKey('library-sharing-select-all')),
    );
    expect(selectAll.label, 'Select all');
    expect(selectAll.isSelected, isTrue);
    expect(selectAll.onTap, isNull);
    expect(find.text('Unselect all'), findsNothing);

    final selectedCount = tester.widget<SelectionSummaryChipComponent>(
      find.byKey(const ValueKey('library-sharing-selected-count')),
    );
    expect(selectedCount.label, '2 selected');

    await tester.tap(
      find.byKey(const ValueKey('library-sharing-selected-count')),
    );
    await tester.pumpAndSettle();

    expect(controller.selectedCount, 0);
    expect(
      tester
          .widget<SelectionSummaryChipComponent>(
            find.byKey(const ValueKey('library-sharing-select-all')),
          )
          .isSelected,
      isFalse,
    );
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

  testWidgets('stop-sharing confirmation returns the destructive choice', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await confirmStopLibrarySharing(
                  context: context,
                  count: 3,
                );
              },
              child: const Text('Open confirmation'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open confirmation'));
    await tester.pumpAndSettle();

    expect(find.text('Stop sharing 3 albums?'), findsOneWidget);
    expect(
      find.text(
        "They'll lose these albums, and any photos they added leave with them. You can share again later.",
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Stop sharing'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('keeps scrollable content above the selection sheet', (
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
    expect(scrollView, findsOneWidget);
    expect(selectionSheet, findsOneWidget);
    expect(
      tester.getBottomLeft(scrollView).dy,
      lessThanOrEqualTo(tester.getTopLeft(selectionSheet).dy),
    );
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
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
}

class _LayoutTestLibrarySharingController extends LibrarySharingController {
  _LayoutTestLibrarySharingController({bool isShared = true})
    : super(
        recipient: librarySharingTestRecipient,
        repository: FakeLibrarySharingRepository([
          librarySharingTestAlbum(
            1,
            recipientRole: isShared ? CollectionParticipantRole.viewer : null,
          ),
        ]),
      );

  @override
  List<Collection> get visibleAlbums => const [];
}

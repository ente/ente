import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/ui/components/bottom_action_bar/action_bar_widget.dart";
import "package:photos/ui/components/bottom_action_bar/selection_action_sheet.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/utils/share_util.dart";

void main() {
  testWidgets("opens a preview, collapses on gallery scroll, and expands", (
    tester,
  ) async {
    final gallery = ScrollController();
    addTearDown(gallery.dispose);
    var tapped = "";
    await _pumpSheet(tester, gallery, onTap: (label) => tapped = label);
    final sheet = tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );
    final controller = sheet.controller!;
    expect(controller.size, sheet.initialChildSize);
    gallery.jumpTo(30);
    await tester.pumpAndSettle();
    expect(controller.size, sheet.initialChildSize);
    await tester.tapAt(const Offset(180, 660));
    expect(tapped, isEmpty);
    await tester.tap(find.text("Share"));
    expect(tapped, "Share");
    await tester.dragFrom(const Offset(180, 200), const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(gallery.offset, greaterThan(0));
    expect(controller.size, sheet.minChildSize);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -320));
    await tester.pumpAndSettle();
    expect(controller.size, sheet.maxChildSize);
    await tester.tap(find.text("Guest view"));
    expect(tapped, "Guest view");
    final galleryOffset = gallery.offset;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 330));
    await tester.pumpAndSettle();
    expect(gallery.offset, galleryOffset);
    expect(controller.size, sheet.minChildSize);
    expect(tester.takeException(), isNull);
  });

  testWidgets("contains tablets, split view, and large text while resizing", (
    tester,
  ) async {
    final gallery = ScrollController();
    addTearDown(gallery.dispose);
    final shareKey = GlobalKey();
    DraggableScrollableController? controller;
    var tapped = "";
    for (final (size, padding, width) in [
      (const Size(740, 280), EdgeInsets.zero, 640.0),
      (
        const Size(1024, 1366),
        const EdgeInsets.only(top: 24, bottom: 20),
        640.0,
      ),
      (const Size(1366, 1024), const EdgeInsets.all(24), 640.0),
      (
        const Size(320, 1024),
        const EdgeInsets.only(top: 24, bottom: 20),
        320.0,
      ),
    ]) {
      await _pumpSheet(
        tester,
        gallery,
        size: size,
        padding: padding,
        textScale: 2,
        dark: true,
        shareKey: shareKey,
        onTap: (label) => tapped = label,
      );
      final sheet = tester.widget<DraggableScrollableSheet>(
        find.byType(DraggableScrollableSheet),
      );
      controller ??= sheet.controller;
      expect(sheet.controller, same(controller));
      sheet.controller!.jumpTo(sheet.maxChildSize);
      final scrollable = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      );
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pumpAndSettle();
      final material = find.descendant(
        of: find.byType(SelectionActionSheet),
        matching: find.byType(Material),
      );
      final rect = tester.getRect(material);
      expect(rect.width, width);
      expect(rect.left, (size.width - width) / 2);
      expect(rect.bottom, size.height);
      expect(rect.top, greaterThanOrEqualTo(padding.top + kToolbarHeight));
      final origin = shareButtonRect(tester.element(material), shareKey);
      expect(origin.isEmpty, isFalse);
      expect(rect.contains(origin.center), isTrue);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Guest view"));
      expect(tapped, "Guest view");
      expect(gallery.offset, 0);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets("preserves hidden and disabled actions and reduced motion", (
    tester,
  ) async {
    final gallery = ScrollController();
    addTearDown(gallery.dispose);
    var tapped = "";
    await _pumpSheet(
      tester,
      gallery,
      reduceMotion: true,
      onTap: (label) => tapped = label,
    );
    expect(find.text("Hidden action"), findsNothing);
    await tester.tap(find.text("Send link"));
    expect(tapped, isEmpty);
    final sheet = tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );
    await tester.tap(find.bySemanticsLabel("More"));
    await tester.pump();
    expect(sheet.controller!.size, sheet.maxChildSize);
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.text("Send link")),
      matchesSemantics(
        label: "Send link",
        isButton: true,
        hasEnabledState: true,
      ),
    );
    semantics.dispose();
    await _pumpSheet(
      tester,
      gallery,
      onTap: (label) => tapped = label,
      actions: [
        for (final label in ["Delete", "Reject suggestions"])
          SelectionSheetAction(
            labelText: label,
            iconWidget: const Icon(Icons.circle),
            onTap: () => tapped = label,
          ),
      ],
    );
    await tester.tap(find.text("Reject suggestions"));
    expect(tapped, "Reject suggestions");
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: gallery,
            children: const [SizedBox(height: 2000)],
          ),
        ),
      ),
    );
    gallery.jumpTo(10);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpSheet(
  WidgetTester tester,
  ScrollController gallery, {
  Size size = const Size(375, 667),
  EdgeInsets padding = EdgeInsets.zero,
  double textScale = 1,
  bool reduceMotion = false,
  bool dark = false,
  List<SelectionSheetAction>? actions,
  GlobalKey? shareKey,
  required ValueChanged<String> onTap,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  const labels = [
    "Share",
    "Send link",
    "Favourite",
    "Delete",
    "Add to album",
    "Hide",
    "Archive",
    "Download",
    "Add person",
    "Edit time",
    "Edit location",
    "Guest view",
  ];
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? darkThemeData : lightThemeData,
      localizationsDelegates: StringsLocalizations.localizationsDelegates,
      supportedLocales: StringsLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
          padding: padding,
          viewPadding: padding,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: GalleryBoundariesProvider(
          child: Builder(
            builder: (context) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => GalleryBoundariesProvider.of(
                  context,
                )!.setScrollController(gallery),
              );
              return Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  ListView(
                    controller: gallery,
                    children: [
                      Container(height: 2000, color: Colors.transparent),
                    ],
                  ),
                  SelectionActionSheet(
                    selectionControls: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final (label, semanticLabel, icon) in [
                            ("All", "Select all", Icons.check_circle),
                            ("3", "Cancel", Icons.close),
                          ])
                            Flexible(
                              child: SelectionControlChip(
                                label: label,
                                semanticLabel: semanticLabel,
                                icon: Icon(icon),
                                onTap: () {},
                              ),
                            ),
                        ],
                      ),
                    ),
                    actions:
                        actions ??
                        [
                          for (final (index, label) in labels.indexed)
                            SelectionSheetAction(
                              key: index == 0 ? shareKey : null,
                              labelText: label,
                              iconWidget: const Icon(Icons.circle),
                              gridOrder: index < 8 ? index : null,
                              isCritical: label == "Delete",
                              onTap: label == "Send link"
                                  ? null
                                  : () => onTap(label),
                            ),
                          SelectionSheetAction(
                            labelText: "Hidden action",
                            iconWidget: const Icon(Icons.circle),
                            shouldShow: false,
                            onTap: () => onTap("Hidden action"),
                          ),
                        ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final boundaries = tester.state<GalleryBoundariesProviderState>(
    find.byType(GalleryBoundariesProvider),
  );
  final sheet = tester.widget<DraggableScrollableSheet>(
    find.byType(DraggableScrollableSheet),
  );
  expect(
    boundaries.selectionSheetMinHeightNotifier.value,
    closeTo(sheet.minChildSize * size.height, 0.01),
  );
}

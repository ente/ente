import "package:flutter/material.dart";
import "package:flutter/semantics.dart" show SemanticsAction;
import "package:flutter/services.dart" show SystemChannels;
import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/viewer/file/file_viewer_filmstrip.dart";
import "package:photos/ui/viewer/file/file_viewer_filmstrip_event.dart";

void main() {
  test("scales with the shortest side and caps large-screen growth", () {
    final phonePortrait = FileViewerFilmstripLayout.forAvailableSize(
      const Size(390, 844),
    );
    final phoneLandscape = FileViewerFilmstripLayout.forAvailableSize(
      const Size(844, 390),
    );
    final iPadMini = FileViewerFilmstripLayout.forAvailableSize(
      const Size(744, 1133),
    );
    final largeIPad = FileViewerFilmstripLayout.forAvailableSize(
      const Size(1032, 1376),
    );

    expect(phonePortrait, FileViewerFilmstripLayout.compact);
    expect(phoneLandscape, FileViewerFilmstripLayout.compact);
    expect(iPadMini.scale, closeTo(1.24, 0.001));
    expect(largeIPad.scale, 1.5);
  });

  testWidgets("centers the selected item and exposes adjustable semantics", (
    tester,
  ) async {
    final key = GlobalKey<_FilmstripHarnessState>();
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _TestApp(
          child: _FilmstripHarness(key: key, itemCount: 20, selectedIndex: 7),
        ),
      );
      await tester.pumpAndSettle();

      _expectCentered(tester, 7);
      expect(tester.getSize(find.byKey(fileViewerFilmstripListKey)).height, 45);
      expect(
        tester
                .getCenter(find.byKey(const ValueKey("filmstrip-test-item-8")))
                .dx -
            tester
                .getCenter(find.byKey(const ValueKey("filmstrip-test-item-7")))
                .dx,
        closeTo(33, 0.01),
      );
      expect(_thumbnailSize(tester, 7), const Size(34, 43));
      expect(_thumbnailSize(tester, 8), const Size(29, 35));
      final semanticsNode = tester.getSemantics(
        find.byKey(fileViewerFilmstripKey),
      );
      final semanticsData = semanticsNode.getSemanticsData();
      expect(semanticsData.label, "Photo chooser");
      expect(semanticsData.value, "Photo 8 of 20");
      expect(semanticsData.hasAction(SemanticsAction.increase), isTrue);
      expect(semanticsData.hasAction(SemanticsAction.decrease), isTrue);

      semanticsNode.owner!.performAction(
        semanticsNode.id,
        SemanticsAction.increase,
      );
      await tester.pumpAndSettle();
      expect(key.currentState!.selections.last.index, 8);
      _expectCentered(tester, 8);

      final updatedSemanticsNode = tester.getSemantics(
        find.byKey(fileViewerFilmstripKey),
      );
      expect(updatedSemanticsNode.getSemanticsData().value, "Photo 9 of 20");
      updatedSemanticsNode.owner!.performAction(
        updatedSemanticsNode.id,
        SemanticsAction.decrease,
      );
      await tester.pumpAndSettle();
      expect(key.currentState!.selections, [
        (index: 8, type: FileViewerFilmstripEventType.tap),
        (index: 7, type: FileViewerFilmstripEventType.tap),
      ]);
      _expectCentered(tester, 7);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets("a tap selects immediately and keeps the size animation", (
    tester,
  ) async {
    final key = GlobalKey<_FilmstripHarnessState>();
    final haptics = _installHapticSpy();
    await tester.pumpWidget(
      _TestApp(
        child: _FilmstripHarness(key: key, itemCount: 20, selectedIndex: 7),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey("filmstrip-test-item-8")));

    expect(key.currentState!.selections.single, (
      index: 8,
      type: FileViewerFilmstripEventType.tap,
    ));
    await tester.pump();
    expect(_thumbnailSize(tester, 8), const Size(29, 35));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 60));
    final transitioningSize = _thumbnailSize(tester, 8);
    expect(transitioningSize.width, inExclusiveRange(29, 34));
    expect(transitioningSize.height, inExclusiveRange(35, 43));
    await tester.pumpAndSettle();

    expect(key.currentState!.selections, [
      (index: 8, type: FileViewerFilmstripEventType.tap),
    ]);
    expect(haptics.count, 1);
    _expectCentered(tester, 8);
    expect(_thumbnailSize(tester, 8), const Size(34, 43));
  });

  testWidgets("recenters the selected item when its layout changes", (
    tester,
  ) async {
    final key = GlobalKey<_FilmstripHarnessState>();
    await tester.pumpWidget(
      _TestApp(
        child: _FilmstripHarness(key: key, itemCount: 20, selectedIndex: 7),
      ),
    );
    await tester.pumpAndSettle();

    final largeLayout = FileViewerFilmstripLayout.forAvailableSize(
      const Size(1032, 1376),
    );
    key.currentState!.update(layout: largeLayout);
    await tester.pumpAndSettle();

    _expectCentered(tester, 7);
    expect(tester.getSize(find.byKey(fileViewerFilmstripListKey)).height, 67.5);
    expect(_thumbnailSize(tester, 7), const Size(51, 64.5));
    expect(
      tester.getCenter(find.byKey(const ValueKey("filmstrip-test-item-8"))).dx -
          tester
              .getCenter(find.byKey(const ValueKey("filmstrip-test-item-7")))
              .dx,
      closeTo(49.5, 0.01),
    );
  });

  testWidgets("sizes thumbnails continuously by their distance from center", (
    tester,
  ) async {
    final key = GlobalKey<_FilmstripHarnessState>();
    final haptics = _installHapticSpy();
    await tester.pumpWidget(
      _TestApp(
        child: _FilmstripHarness(key: key, itemCount: 20, selectedIndex: 7),
      ),
    );
    await tester.pumpAndSettle();

    final position = _filmstripPosition(tester);
    final initialOffset = position.pixels;
    final itemPitch =
        tester
            .getCenter(find.byKey(const ValueKey("filmstrip-test-item-8")))
            .dx -
        tester
            .getCenter(find.byKey(const ValueKey("filmstrip-test-item-7")))
            .dx;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(fileViewerFilmstripListKey)),
    );
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();

    Future<void> moveTo(double itemFraction) async {
      final targetOffset = initialOffset + (itemPitch * itemFraction);
      await gesture.moveBy(Offset(position.pixels - targetOffset, 0));
      await tester.pump();
    }

    await moveTo(0.25);
    final outgoingAt25 = _thumbnailSize(tester, 7);
    final incomingAt25 = _thumbnailSize(tester, 8);
    expect(outgoingAt25.width, inExclusiveRange(29, 34));
    expect(incomingAt25.width, inExclusiveRange(29, outgoingAt25.width));
    expect(key.currentState!.selections.map((event) => event.type), [
      FileViewerFilmstripEventType.scrubStart,
    ]);
    expect(haptics.count, 0);

    await moveTo(0.45);
    final outgoingAt45 = _thumbnailSize(tester, 7);
    final incomingAt45 = _thumbnailSize(tester, 8);
    expect(outgoingAt45.width, lessThan(outgoingAt25.width));
    expect(incomingAt45.width, greaterThan(incomingAt25.width));
    expect(haptics.count, 0);

    await moveTo(0.55);
    final outgoingAt55 = _thumbnailSize(tester, 7);
    final incomingAt55 = _thumbnailSize(tester, 8);
    expect(outgoingAt55.width, lessThan(outgoingAt45.width));
    expect(incomingAt55.width, greaterThan(incomingAt45.width));
    expect((outgoingAt55.width - outgoingAt45.width).abs(), lessThan(2));
    expect((incomingAt55.width - incomingAt45.width).abs(), lessThan(2));
    expect(key.currentState!.selections.last, (
      index: 8,
      type: FileViewerFilmstripEventType.scrubPreview,
    ));
    expect(haptics.count, 1);

    await moveTo(0.75);
    expect(_thumbnailSize(tester, 7).width, lessThan(outgoingAt55.width));
    expect(_thumbnailSize(tester, 8).width, greaterThan(incomingAt55.width));
    expect(haptics.count, 1);

    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(key.currentState!.selections.last, (
      index: 8,
      type: FileViewerFilmstripEventType.scrubCommit,
    ));
    expect(haptics.count, 1);
    _expectCentered(tester, 8);
  });

  testWidgets("scrub focus changes do not rebuild itemBuilder children", (
    tester,
  ) async {
    final key = GlobalKey<_FilmstripHarnessState>();
    final buildCounts = <int, int>{};
    await tester.pumpWidget(
      _TestApp(
        child: _FilmstripHarness(
          key: key,
          itemCount: 20,
          selectedIndex: 7,
          onItemBuild: (index) {
            buildCounts.update(index, (count) => count + 1, ifAbsent: () => 1);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final initialBuilds = {7: buildCounts[7]!, 8: buildCounts[8]!};

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(fileViewerFilmstripListKey)),
    );
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-33, 0));
    await tester.pump();

    expect(key.currentState!.selections.last, (
      index: 8,
      type: FileViewerFilmstripEventType.scrubPreview,
    ));
    expect(buildCounts[7], initialBuilds[7]);
    expect(buildCounts[8], initialBuilds[8]);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets("scrubbing previews and ticks each newly centered thumbnail", (
    tester,
  ) async {
    final key = GlobalKey<_FilmstripHarnessState>();
    final haptics = _installHapticSpy();
    await tester.pumpWidget(
      _TestApp(
        child: _FilmstripHarness(key: key, itemCount: 20, selectedIndex: 7),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(fileViewerFilmstripListKey)),
    );
    // The first move starts Flutter's drag recognizer; the second one scrolls.
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-33, 0));
    await tester.pump();

    expect(
      key.currentState!.selections
          .where(
            (event) => event.type == FileViewerFilmstripEventType.scrubStart,
          )
          .length,
      1,
    );
    var previewsBeforeUp = key.currentState!.selections
        .where(
          (event) => event.type == FileViewerFilmstripEventType.scrubPreview,
        )
        .toList();
    expect(previewsBeforeUp.map((event) => event.index), [8]);
    expect(haptics.count, 1);
    _expectNearestToStripCenter(tester, 8);

    await gesture.moveBy(const Offset(-33, 0));
    await tester.pump();

    previewsBeforeUp = key.currentState!.selections
        .where(
          (event) => event.type == FileViewerFilmstripEventType.scrubPreview,
        )
        .toList();
    expect(previewsBeforeUp.map((event) => event.index), [8, 9]);
    expect(haptics.count, 2);

    await gesture.moveBy(const Offset(33, 0));
    await tester.pump();

    previewsBeforeUp = key.currentState!.selections
        .where(
          (event) => event.type == FileViewerFilmstripEventType.scrubPreview,
        )
        .toList();
    expect(previewsBeforeUp.map((event) => event.index), [8, 9, 8]);
    expect(haptics.count, 3);

    final previewIndex = previewsBeforeUp.last.index;
    _expectNearestToStripCenter(tester, previewIndex);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(haptics.count, previewsBeforeUp.length);
    expect(key.currentState!.selections.last, (
      index: previewIndex,
      type: FileViewerFilmstripEventType.scrubCommit,
    ));
    expect(
      key.currentState!.selections
          .where(
            (event) => event.type == FileViewerFilmstripEventType.scrubCommit,
          )
          .length,
      1,
    );
    _expectCentered(tester, previewIndex);
  });

  testWidgets("caps fling velocity at 800 and extends Android coast", (
    tester,
  ) async {
    await tester.pumpWidget(
      const _TestApp(child: _FilmstripHarness(itemCount: 20, selectedIndex: 7)),
    );
    await tester.pumpAndSettle();

    final position = _filmstripPosition(tester);
    final physics = position.physics;
    expect(physics.maxFlingVelocity, 800);

    final cappedSimulation = physics.createBallisticSimulation(position, 5000);
    expect(cappedSimulation, isNotNull);
    expect(cappedSimulation!.dx(0).abs(), lessThanOrEqualTo(800.01));

    final tunedSimulation = physics.createBallisticSimulation(position, 500)!;
    final baselineSimulation = physics.parent!.createBallisticSimulation(
      position,
      500,
    )!;
    expect(tunedSimulation.dx(0), closeTo(baselineSimulation.dx(0), 0.01));
    expect(
      tunedSimulation.dx(0.25).abs(),
      greaterThan(baselineSimulation.dx(0.25).abs()),
    );
    final tunedSettlingTime = _settlingTime(tunedSimulation, start: 0.25);
    final baselineSettlingTime = _settlingTime(baselineSimulation, start: 0.25);
    expect(
      tunedSettlingTime / baselineSettlingTime,
      inInclusiveRange(1.7, 2.0),
    );
  });

  testWidgets("iOS and Android filmstrips have the same fling deceleration", (
    tester,
  ) async {
    final simulations = <TargetPlatform, List<Simulation>>{};
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      await tester.pumpWidget(
        _TestApp(
          platform: platform,
          child: const _FilmstripHarness(itemCount: 100, selectedIndex: 50),
        ),
      );
      await tester.pumpAndSettle();

      final position = _filmstripPosition(tester);
      simulations[platform] = [
        for (final velocity in [-500.0, 500.0, 5000.0])
          position.physics.createBallisticSimulation(position, velocity)!,
      ];
    }

    final android = simulations[TargetPlatform.android]!;
    final ios = simulations[TargetPlatform.iOS]!;
    for (var index = 0; index < android.length; index++) {
      for (final time in [0.0, 0.1, 0.25, 0.5, 1.0]) {
        expect(ios[index].x(time), closeTo(android[index].x(time), 0.01));
        expect(ios[index].dx(time), closeTo(android[index].dx(time), 0.01));
      }
      expect(
        _settlingTime(ios[index], start: 0),
        closeTo(_settlingTime(android[index], start: 0), 0.01),
      );
    }
  });

  testWidgets("a second fling keeps moving while the strip is coasting", (
    tester,
  ) async {
    await tester.pumpWidget(
      const _TestApp(
        child: _FilmstripHarness(itemCount: 100, selectedIndex: 50),
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(fileViewerFilmstripListKey);
    final position = _filmstripPosition(tester);
    const motion = Offset(-60, 0);
    const speed = 400.0;
    await tester.fling(list, motion, speed);
    await tester.pump();
    final firstLaunchVelocity = position.activity!.velocity;
    await tester.pump(const Duration(milliseconds: 10));
    final coastingVelocity = position.activity!.velocity;
    expect(position.isScrollingNotifier.value, isTrue);
    expect(coastingVelocity.sign, firstLaunchVelocity.sign);
    expect(
      coastingVelocity.abs(),
      inExclusiveRange(0, firstLaunchVelocity.abs()),
    );

    await tester.fling(
      list,
      motion,
      speed,
      // Run the replacement gesture without an intermediate frame so the
      // interrupted fling's queued alignment races with its new ballistic.
      frameInterval: const Duration(seconds: 1),
    );
    await tester.pump();

    final repeatedLaunchVelocity = position.activity!.velocity;
    expect(repeatedLaunchVelocity.sign, firstLaunchVelocity.sign);
    expect(
      repeatedLaunchVelocity.abs(),
      greaterThan(firstLaunchVelocity.abs() * 1.05),
    );
    expect(repeatedLaunchVelocity.abs(), lessThanOrEqualTo(800.01));
  });

  testWidgets("a fling previews during its coast and commits once at rest", (
    tester,
  ) async {
    final key = GlobalKey<_FilmstripHarnessState>();
    final haptics = _installHapticSpy();
    await tester.pumpWidget(
      _TestApp(
        child: _FilmstripHarness(key: key, itemCount: 100, selectedIndex: 50),
      ),
    );
    await tester.pumpAndSettle();

    await tester.fling(
      find.byKey(fileViewerFilmstripListKey),
      const Offset(-80, 0),
      400,
    );
    await tester.pump();

    final position = _filmstripPosition(tester);
    final previewsAtLaunch = key.currentState!.selections
        .where(
          (event) => event.type == FileViewerFilmstripEventType.scrubPreview,
        )
        .length;
    expect(position.isScrollingNotifier.value, isTrue);
    expect(
      key.currentState!.selections.where(
        (event) => event.type == FileViewerFilmstripEventType.scrubCommit,
      ),
      isEmpty,
    );

    await tester.pump(const Duration(milliseconds: 150));
    expect(position.isScrollingNotifier.value, isTrue);
    expect(
      key.currentState!.selections
          .where(
            (event) => event.type == FileViewerFilmstripEventType.scrubPreview,
          )
          .length,
      greaterThan(previewsAtLaunch),
    );
    expect(
      key.currentState!.selections.where(
        (event) => event.type == FileViewerFilmstripEventType.scrubCommit,
      ),
      isEmpty,
    );

    await tester.pumpAndSettle();

    final selections = key.currentState!.selections;
    final previews = selections
        .where(
          (event) => event.type == FileViewerFilmstripEventType.scrubPreview,
        )
        .toList();
    final commits = selections
        .where(
          (event) => event.type == FileViewerFilmstripEventType.scrubCommit,
        )
        .toList();
    expect(
      selections
          .where(
            (event) => event.type == FileViewerFilmstripEventType.scrubStart,
          )
          .length,
      1,
    );
    expect(commits, hasLength(1));
    expect(selections.last, commits.single);
    expect(commits.single.index, previews.last.index);
    expect(haptics.count, previews.length);
    _expectCentered(tester, commits.single.index);
  });

  testWidgets("holding a coasting strip does not start a center snap", (
    tester,
  ) async {
    final key = GlobalKey<_FilmstripHarnessState>();
    await tester.pumpWidget(
      _TestApp(
        child: _FilmstripHarness(key: key, itemCount: 100, selectedIndex: 50),
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(fileViewerFilmstripListKey);
    final position = _filmstripPosition(tester);
    await tester.fling(list, const Offset(-50, 0), 400);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(position.isScrollingNotifier.value, isTrue);

    final gesture = await tester.startGesture(tester.getCenter(list));
    final heldOffset = position.pixels;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(position.pixels, closeTo(heldOffset, 0.01));

    await gesture.cancel();
    await tester.pumpAndSettle();
    _expectCentered(tester, key.currentState!.selectedIndex);
  });

  testWidgets("a drag that stays centered still ends its scrub session", (
    tester,
  ) async {
    final key = GlobalKey<_FilmstripHarnessState>();
    final haptics = _installHapticSpy();
    await tester.pumpWidget(
      _TestApp(
        child: _FilmstripHarness(key: key, itemCount: 20, selectedIndex: 7),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(fileViewerFilmstripListKey)),
    );
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(key.currentState!.selections, [
      (index: 7, type: FileViewerFilmstripEventType.scrubStart),
      (index: 7, type: FileViewerFilmstripEventType.scrubCommit),
    ]);
    expect(haptics.count, 0);
    _expectCentered(tester, 7);
  });

  testWidgets("realigns safely when the selection or item count changes", (
    tester,
  ) async {
    final key = GlobalKey<_FilmstripHarnessState>();
    final haptics = _installHapticSpy();
    await tester.pumpWidget(
      _TestApp(
        child: _FilmstripHarness(key: key, itemCount: 20, selectedIndex: 7),
      ),
    );
    await tester.pumpAndSettle();

    key.currentState!.update(selectedIndex: 19);
    await tester.pumpAndSettle();
    _expectCentered(tester, 19);
    expect(key.currentState!.selections, isEmpty);

    key.currentState!.update(itemCount: 4, selectedIndex: 3);
    await tester.pumpAndSettle();
    _expectCentered(tester, 3);
    expect(key.currentState!.selections, isEmpty);

    key.currentState!.update(itemCount: 0, selectedIndex: 0);
    await tester.pumpAndSettle();
    expect(find.byKey(fileViewerFilmstripListKey), findsNothing);

    key.currentState!.update(itemCount: 5, selectedIndex: 2);
    await tester.pumpAndSettle();
    _expectCentered(tester, 2);
    expect(haptics.count, 0);
  });
}

void _expectCentered(WidgetTester tester, int index) {
  final itemCenter = tester.getCenter(
    find.byKey(ValueKey("filmstrip-test-item-$index")),
  );
  final stripCenter = tester.getCenter(find.byKey(fileViewerFilmstripListKey));
  expect(itemCenter.dx, closeTo(stripCenter.dx, 0.5));
}

Size _thumbnailSize(WidgetTester tester, int index) {
  return tester.getSize(
    find.byKey(ValueKey("filmstrip-test-thumbnail-$index")),
  );
}

ScrollPosition _filmstripPosition(WidgetTester tester) {
  return tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byKey(fileViewerFilmstripListKey),
          matching: find.byType(Scrollable),
        ),
      )
      .position;
}

_HapticSpy _installHapticSpy() {
  final spy = _HapticSpy()..install();
  addTearDown(spy.uninstall);
  return spy;
}

double _settlingTime(Simulation simulation, {required double start}) {
  var time = start;
  while (!simulation.isDone(time) && time < 10) {
    time += 0.01;
  }
  if (!simulation.isDone(time)) {
    fail("Simulation did not settle within 10 seconds");
  }
  return time;
}

void _expectNearestToStripCenter(WidgetTester tester, int index) {
  final stripCenter = tester.getCenter(find.byKey(fileViewerFilmstripListKey));
  final builtItems = find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith(
          "filmstrip-test-item-",
        ),
  );
  var nearestIndex = -1;
  var nearestDistance = double.infinity;
  for (final element in builtItems.evaluate()) {
    final key = element.widget.key! as ValueKey<String>;
    final itemIndex = int.parse(key.value.split("-").last);
    final distance = (tester.getCenter(find.byKey(key)).dx - stripCenter.dx)
        .abs();
    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearestIndex = itemIndex;
    }
  }
  expect(index, nearestIndex);
}

class _TestApp extends StatelessWidget {
  final Widget child;
  final TargetPlatform? platform;

  const _TestApp({required this.child, this.platform});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(platform: platform),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: SizedBox(width: 380, child: child)),
      ),
    );
  }
}

class _HapticSpy {
  int count = 0;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == "HapticFeedback.vibrate") count++;
          return null;
        });
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  }
}

class _FilmstripHarness extends StatefulWidget {
  final int itemCount;
  final int selectedIndex;
  final ValueChanged<int>? onItemBuild;

  const _FilmstripHarness({
    required this.itemCount,
    required this.selectedIndex,
    this.onItemBuild,
    super.key,
  });

  @override
  State<_FilmstripHarness> createState() => _FilmstripHarnessState();
}

class _FilmstripHarnessState extends State<_FilmstripHarness> {
  late int itemCount = widget.itemCount;
  late int selectedIndex = widget.selectedIndex;
  FileViewerFilmstripLayout layout = FileViewerFilmstripLayout.compact;
  final selections = <FileViewerFilmstripEvent>[];

  void update({
    int? itemCount,
    int? selectedIndex,
    FileViewerFilmstripLayout? layout,
  }) {
    setState(() {
      this.itemCount = itemCount ?? this.itemCount;
      this.selectedIndex = selectedIndex ?? this.selectedIndex;
      this.layout = layout ?? this.layout;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FileViewerFilmstrip(
      layout: layout,
      itemCount: itemCount,
      selectedIndex: selectedIndex,
      semanticLabel: "Photo chooser",
      semanticValueBuilder: (current, total) => "Photo $current of $total",
      itemKeyBuilder: (index) => ValueKey("filmstrip-test-item-$index"),
      itemBuilder: (context, index) {
        widget.onItemBuild?.call(index);
        return ColoredBox(
          key: ValueKey("filmstrip-test-thumbnail-$index"),
          color: Color(0xFF000000 + index),
        );
      },
      onEvent: (event) {
        selections.add(event);
        if (event.type == FileViewerFilmstripEventType.tap ||
            event.type == FileViewerFilmstripEventType.scrubCommit) {
          setState(() => selectedIndex = event.index);
        }
      },
    );
  }
}

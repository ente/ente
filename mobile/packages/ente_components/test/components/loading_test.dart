import "dart:ui" show SemanticsRole;

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  Widget app(Widget child) => MaterialApp(
    theme: ComponentTheme.lightTheme(),
    home: Scaffold(body: Center(child: child)),
  );
  final paint = find.descendant(
    of: find.byType(LoadingComponent),
    matching: find.byType(CustomPaint),
  );
  const tick = Duration(milliseconds: 1);

  testWidgets("LoadingComponent paints a rotating ring in the three sizes", (
    tester,
  ) async {
    for (final sample in {
      LoadingComponentSize.small: 16.0,
      LoadingComponentSize.medium: 24.0,
      LoadingComponentSize.large: 40.0,
    }.entries) {
      await tester.pumpWidget(app(LoadingComponent(size: sample.key)));
      expect(paint, findsOneWidget);
      expect(
        tester.getSize(find.byType(LoadingComponent)),
        Size.square(sample.value),
      );
      expect(tester.hasRunningAnimations, isTrue);
    }
  });

  testWidgets("showLoadingComponent updates in place and hides", (
    tester,
  ) async {
    await tester.pumpWidget(app(const SizedBox()));
    final handle = showLoadingComponent(
      tester.element(find.byType(Scaffold)),
      "Deleting 3 items",
    );
    await tester.pump();
    await tester.pump(Motion.standard);
    expect(handle.isShowing(), isTrue);
    expect(find.text("Deleting 3 items"), findsOneWidget);

    handle.update(message: "Almost done");
    await tester.pump();
    expect(find.text("Almost done"), findsOneWidget);

    final hidden = handle.hide();
    await tester.pump();
    await tester.pump(Motion.standard);
    await tester.pump(tick);
    await hidden;
    expect(handle.isShowing(), isFalse);
    expect(find.byType(LoadingComponent), findsNothing);
  });

  testWidgets("showLoadingComponent honours isDismissible", (tester) async {
    await tester.pumpWidget(app(const SizedBox()));
    final context = tester.element(find.byType(Scaffold));

    final fixed = showLoadingComponent(context, "Creating link");
    await tester.pump();
    await tester.pump(Motion.standard);
    await tester.pump(tick);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(fixed.isShowing(), isTrue);
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    await tester.pump(Motion.standard);
    expect(find.text("Creating link"), findsOneWidget);
    final hidden = fixed.hide();
    await tester.pump();
    await tester.pump(Motion.standard);
    await tester.pump(tick);
    await hidden;

    final dismissible = showLoadingComponent(
      context,
      "Creating link",
      isDismissible: true,
    );
    await tester.pump();
    await tester.pump(Motion.standard);
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    await tester.pump(Motion.standard);
    await tester.pump(tick);
    expect(find.text("Creating link"), findsNothing);
    expect(dismissible.isShowing(), isFalse);
    dismissible.update(message: "Still safe after dismissal");
    await dismissible.hide();
  });

  testWidgets("LoadingComponent exposes its label and spinner role", (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      app(const LoadingComponent(semanticsLabel: "Downloading")),
    );
    expect(
      tester.getSemantics(find.byType(LoadingComponent)),
      isSemantics(label: "Downloading"),
    );
    expect(
      tester
          .getSemantics(find.byType(LoadingComponent))
          .getSemanticsData()
          .role,
      SemanticsRole.loadingSpinner,
    );
    handle.dispose();
  });

  testWidgets("showLoadingComponent uses the caller's theme for every part", (
    tester,
  ) async {
    final local = ComponentTheme.darkTheme(app: ComponentApp.locker);
    final colors = local.extension<ComponentColorTokens>()!.colors;
    await tester.pumpWidget(
      MaterialApp(
        theme: ComponentTheme.lightTheme(),
        home: Theme(
          data: local,
          child: const Scaffold(body: SizedBox()),
        ),
      ),
    );
    showLoadingComponent(tester.element(find.byType(Scaffold)), "Opening");
    await tester.pump();
    await tester.pump(Motion.standard);

    final ring = tester.widget<CustomPaint>(paint);
    expect((ring.painter! as dynamic).color, colors.primary);
    final card = tester.widget<Container>(
      find.ancestor(of: find.text("Opening"), matching: find.byType(Container)),
    );
    expect((card.decoration! as BoxDecoration).color, colors.backgroundBase);
  });

  testWidgets("showLoadingComponent establishes a semantic route", (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(app(const SizedBox()));
    showLoadingComponent(tester.element(find.byType(Scaffold)), "Opening");
    await tester.pump();
    await tester.pump(Motion.standard);

    var node = tester.getSemantics(find.text("Opening"));
    final spinnerRole = tester
        .getSemantics(find.byType(LoadingComponent))
        .getSemanticsData()
        .role;
    var scopesRoute = false;
    while (true) {
      scopesRoute |= node.getSemanticsData().flagsCollection.scopesRoute;
      final parent = node.parent;
      if (parent == null) break;
      node = parent;
    }
    semantics.dispose();
    expect(scopesRoute, isTrue);
    expect(spinnerRole, SemanticsRole.loadingSpinner);
  });

  testWidgets("showLoadingComponent keeps focus traversal inside the dialog", (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ComponentTheme.lightTheme(),
        builder: (_, _) => Navigator(
          routeTraversalEdgeBehavior: TraversalEdgeBehavior.leaveFlutterView,
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: SizedBox()),
          ),
        ),
      ),
    );
    showLoadingComponent(tester.element(find.byType(Scaffold)), "Opening");
    await tester.pump();
    await tester.pump(Motion.standard);
    expect(
      FocusScope.of(tester.element(find.text("Opening"))).traversalEdgeBehavior,
      TraversalEdgeBehavior.closedLoop,
    );
  });

  testWidgets("download progress remains in the message and null keeps it", (
    tester,
  ) async {
    await tester.pumpWidget(app(const SizedBox()));
    final handle = showLoadingComponent(
      tester.element(find.byType(Scaffold)),
      "Downloading",
    );
    await tester.pump();
    await tester.pump(Motion.standard);

    handle.update(message: "Downloading 45%");
    await tester.pump();
    handle.update(message: null);
    await tester.pump();
    expect(find.text("Downloading 45%"), findsOneWidget);
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets(
    "hide before the first frame completes without popping the page",
    (tester) async {
      await tester.pumpWidget(app(const Text("Page")));
      final handle = showLoadingComponent(
        tester.element(find.byType(Scaffold)),
        "Opening",
      );
      final hidden = handle.hide();
      await tester.pumpAndSettle();
      await hidden;
      expect(handle.isShowing(), isFalse);
      expect(find.text("Opening"), findsNothing);
      expect(find.text("Page"), findsOneWidget);
    },
  );

  testWidgets("hide leaves a newer page on the navigator", (tester) async {
    await tester.pumpWidget(app(const Text("Page")));
    final context = tester.element(find.byType(Scaffold));
    final handle = showLoadingComponent(context, "Opening");
    await tester.pump();
    await tester.pump(Motion.standard);
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const Scaffold(body: Text("New page"))),
    );
    await tester.pumpAndSettle();

    final hidden = handle.hide();
    await tester.pumpAndSettle();
    await hidden;
    expect(handle.isShowing(), isFalse);
    expect(find.text("New page"), findsOneWidget);
  });

  testWidgets("showLoadingComponent centres the card above the keyboard", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const SizedBox()));
    showLoadingComponent(tester.element(find.byType(Scaffold)), "Opening");
    await tester.pump();
    await tester.pump(Motion.standard);

    final card = find.ancestor(
      of: find.text("Opening"),
      matching: find.byType(Container),
    );
    expect(tester.getCenter(card).dy, 150);
  });
}

import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hugeicons/hugeicons.dart";

void main() {
  testWidgets(
    "ButtonComponent surfaces loading after debounce and blocks repeat taps",
    (tester) async {
      var tapCount = 0;
      final completer = Completer<void>();

      await tester.pumpWidget(
        _wrap(
          ButtonComponent(
            label: "Uploading",
            onTap: () {
              tapCount += 1;
              return completer.future;
            },
          ),
        ),
      );

      await tester.tap(find.text("Uploading"));
      await tester.pump();

      expect(tapCount, 1);
      expect(find.byKey(const ValueKey('loading')), findsNothing);

      await tester.tap(find.text("Uploading"));
      await tester.pump();

      expect(tapCount, 1);

      await tester.pump(const Duration(milliseconds: 299));
      expect(find.byKey(const ValueKey('loading')), findsNothing);

      await tester.pump(const Duration(milliseconds: 1));

      final loadingFinder = find.byKey(const ValueKey('loading'));
      expect(loadingFinder, findsOneWidget);
      expect(
        find.descendant(
          of: loadingFinder,
          matching: find.byType(RotationTransition),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: loadingFinder, matching: find.byType(HugeIcon)),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text("Uploading"), findsOneWidget);
      expect(tester.getSize(find.byType(AnimatedContainer)).height, 52);

      completer.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('success')), findsOneWidget);
    },
  );

  testWidgets(
    "Small ButtonComponent keeps idle width when parent rebuilds during loading",
    (tester) async {
      final completer = Completer<void>();
      var rebuildToken = 0;

      Widget buildButton() {
        return _wrap(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Parent rebuild $rebuildToken"),
              ButtonComponent(
                label: "Uploading",
                size: ButtonComponentSize.small,
                onTap: () => completer.future,
              ),
            ],
          ),
        );
      }

      await tester.pumpWidget(buildButton());
      await tester.pump();

      final idleWidth = tester.getSize(find.byType(AnimatedContainer)).width;

      await tester.tap(find.text("Uploading"));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 200));

      rebuildToken += 1;
      await tester.pumpWidget(buildButton());
      await tester.pump();

      expect(find.byKey(const ValueKey('loading')), findsOneWidget);
      expect(find.text("Uploading"), findsOneWidget);
      expect(tester.getSize(find.byType(AnimatedContainer)).width, idleWidth);

      completer.complete();
    },
  );

  testWidgets(
    "ButtonComponent can hide execution visuals while still blocking taps",
    (tester) async {
      var tapCount = 0;
      final completer = Completer<void>();

      await tester.pumpWidget(
        _wrap(
          ButtonComponent(
            label: "Silent",
            shouldSurfaceExecutionStates: false,
            onTap: () {
              tapCount += 1;
              return completer.future;
            },
          ),
        ),
      );

      await tester.tap(find.text("Silent"));
      await tester.pump(const Duration(milliseconds: 400));

      expect(tapCount, 1);
      expect(find.byKey(const ValueKey('loading')), findsNothing);
      expect(find.text("Silent"), findsOneWidget);

      await tester.tap(find.text("Silent"));
      await tester.pump();

      expect(tapCount, 1);

      completer.complete();
      await tester.pump();
    },
  );

  testWidgets("ButtonComponent resets state after async errors", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ButtonComponent(
          label: "Fail",
          onTap: () async => throw StateError("failed"),
        ),
      ),
    );

    await tester.tap(find.text("Fail"));
    await tester.pump();

    expect(find.text("Fail"), findsOneWidget);
    expect(find.byKey(const ValueKey('loading')), findsNothing);
    expect(find.byKey(const ValueKey('success')), findsNothing);
  });

  testWidgets(
    "ButtonComponent dismisses modal routes after success when configured",
    (tester) async {
      var modalDismissed = false;

      await tester.pumpWidget(
        _wrapModalTestApp(
          onModalDismissed: () => modalDismissed = true,
          child: ButtonComponent(
            label: "Done",
            shouldSurfaceExecutionStates: false,
            dismissModalOnSuccess: true,
            onTap: () {},
          ),
        ),
      );

      await tester.tap(find.text("Open"));
      await tester.pumpAndSettle();

      expect(find.text("Done"), findsOneWidget);

      await tester.tap(find.text("Done"));
      await tester.pumpAndSettle();

      expect(find.text("Open"), findsOneWidget);
      expect(modalDismissed, isTrue);
    },
  );

  testWidgets(
    "ButtonComponent does not dismiss normal page routes when configured",
    (tester) async {
      await tester.pumpWidget(
        _wrapRouteTestApp(
          child: ButtonComponent(
            label: "Save",
            shouldSurfaceExecutionStates: false,
            dismissModalOnSuccess: true,
            onTap: () {},
          ),
        ),
      );

      await tester.tap(find.text("Open"));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Save"));
      await tester.pumpAndSettle();

      expect(find.text("Save"), findsOneWidget);
    },
  );

  testWidgets("ButtonComponent does not dismiss modal routes after errors", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapModalTestApp(
        child: ButtonComponent(
          label: "Fail",
          shouldSurfaceExecutionStates: false,
          dismissModalOnSuccess: true,
          onTap: () async => throw StateError("failed"),
        ),
      ),
    );

    await tester.tap(find.text("Open"));
    await tester.pumpAndSettle();

    await tester.tap(find.text("Fail"));
    await tester.pumpAndSettle();

    expect(find.text("Fail"), findsOneWidget);
  });

  testWidgets("IconButtonComponent resets state after async errors", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        IconButtonComponent(
          icon: const Icon(Icons.add),
          onTap: () async => throw StateError("failed"),
        ),
      ),
    );

    await tester.tap(find.byType(GestureDetector));
    await tester.pump();

    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byKey(const ValueKey('loading')), findsNothing);
    expect(find.byKey(const ValueKey('success')), findsNothing);
  });

  testWidgets("IconButtonComponent surfaces async execution states", (
    tester,
  ) async {
    var tapCount = 0;
    final completer = Completer<void>();

    await tester.pumpWidget(
      _wrap(
        IconButtonComponent(
          icon: const Icon(Icons.add),
          onTap: () {
            tapCount += 1;
            return completer.future;
          },
        ),
      ),
    );

    await tester.tap(find.byType(GestureDetector));
    await tester.pump();

    expect(tapCount, 1);
    expect(find.byKey(const ValueKey('loading')), findsNothing);

    await tester.tap(find.byType(GestureDetector));
    await tester.pump();

    expect(tapCount, 1);

    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('loading')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byIcon(Icons.add), findsNothing);

    completer.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('success')), findsOneWidget);
  });
}

Widget _wrap(
  Widget child, {
  ComponentApp app = ComponentApp.photos,
  Brightness brightness = Brightness.light,
}) {
  return MaterialApp(
    themeAnimationDuration: Duration.zero,
    theme: ComponentTheme.themeForApp(app, brightness: brightness),
    home: Scaffold(body: Center(child: child)),
  );
}

Widget _wrapRouteTestApp({required Widget child}) {
  return MaterialApp(
    themeAnimationDuration: Duration.zero,
    theme: ComponentTheme.themeForApp(ComponentApp.photos),
    home: Scaffold(
      body: Center(
        child: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                await Navigator.of(context).push<Object?>(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(body: Center(child: child)),
                  ),
                );
              },
              child: const Text("Open"),
            );
          },
        ),
      ),
    ),
  );
}

Widget _wrapModalTestApp({
  required Widget child,
  VoidCallback? onModalDismissed,
}) {
  return MaterialApp(
    themeAnimationDuration: Duration.zero,
    theme: ComponentTheme.themeForApp(ComponentApp.photos),
    home: Scaffold(
      body: Center(
        child: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => Center(child: child),
                ).whenComplete(() => onModalDismissed?.call());
              },
              child: const Text("Open"),
            );
          },
        ),
      ),
    ),
  );
}

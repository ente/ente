import "dart:async";
import "dart:ui";

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hugeicons/hugeicons.dart";

void main() {
  testWidgets("ButtonComponent renders label and expected size", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(ButtonComponent(label: "Continue", onTap: () {})),
    );

    expect(find.text("Continue"), findsOneWidget);
    expect(tester.getSize(find.byType(AnimatedContainer)).height, 52);
  });

  testWidgets("Compact ButtonComponent uses 48px geometry and body type", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ButtonComponent(
          label: "Save",
          density: ButtonComponentDensity.compact,
          onTap: () {},
        ),
      ),
    );

    expect(tester.getSize(find.byType(AnimatedContainer)).height, 48);
    final style = tester.widget<Text>(find.text("Save")).style!;
    expect(style.fontWeight, TextStyles.body.fontWeight);
    expect(style.fontSize, TextStyles.body.fontSize);
  });

  testWidgets("ButtonComponent calls onTap when tapped", (tester) async {
    var tapCount = 0;

    await tester.pumpWidget(
      _wrap(ButtonComponent(label: "Save", onTap: () => tapCount += 1)),
    );

    await tester.tap(find.text("Save"));
    await tester.pump();

    expect(tapCount, 1);
  });

  testWidgets("ButtonComponent renders leading content", (tester) async {
    await tester.pumpWidget(
      _wrap(
        ButtonComponent(
          label: "Share",
          leading: const Icon(Icons.share_outlined),
          onTap: () {},
        ),
      ),
    );

    expect(find.text("Share"), findsOneWidget);
    expect(find.byIcon(Icons.share_outlined), findsOneWidget);
  });

  testWidgets(
    "Small ButtonComponent shrink-wraps content without a minimum width",
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          ButtonComponent(
            label: "OK",
            size: ButtonComponentSize.small,
            onTap: () {},
          ),
        ),
      );

      final size = tester.getSize(find.byType(AnimatedContainer));
      expect(size.height, 52);
      expect(size.width, lessThan(100));
    },
  );

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
    "ButtonComponent shows success confirmation for fast actions when enabled",
    (tester) async {
      var tapCount = 0;

      await tester.pumpWidget(
        _wrap(
          ButtonComponent(
            label: "Saved",
            shouldShowSuccessConfirmation: true,
            onTap: () => tapCount += 1,
          ),
        ),
      );

      await tester.tap(find.text("Saved"));
      await tester.pump();

      expect(tapCount, 1);
      expect(find.byType(HugeIcon), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text("Saved"), findsOneWidget);
      expect(tester.getSize(find.byType(AnimatedContainer)).height, 52);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text("Saved"), findsOneWidget);
    },
  );

  testWidgets("ButtonComponent can surface loading without success", (
    tester,
  ) async {
    final completer = Completer<void>();

    await tester.pumpWidget(
      _wrap(
        ButtonComponent(
          label: "Saving",
          shouldShowSuccessState: false,
          onTap: () => completer.future,
        ),
      ),
    );

    await tester.tap(find.text("Saving"));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('loading')), findsOneWidget);

    completer.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const ValueKey('success')), findsNothing);
    expect(find.text("Saving"), findsOneWidget);
  });

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

  testWidgets("ButtonComponent does not dismiss modal routes by default", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapModalTestApp(
        child: ButtonComponent(
          label: "Stay",
          shouldSurfaceExecutionStates: false,
          onTap: () {},
        ),
      ),
    );

    await tester.tap(find.text("Open"));
    await tester.pumpAndSettle();

    await tester.tap(find.text("Stay"));
    await tester.pumpAndSettle();

    expect(find.text("Stay"), findsOneWidget);
  });

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

  testWidgets(
    "ButtonComponent remains disabled when onTap is null or disabled",
    (tester) async {
      var tapCount = 0;

      await tester.pumpWidget(
        _wrap(
          Column(
            children: [
              const ButtonComponent(label: "No callback", onTap: null),
              ButtonComponent(
                label: "Disabled",
                isDisabled: true,
                onTap: () => tapCount += 1,
              ),
            ],
          ),
        ),
      );

      expect(find.text("No callback"), findsOneWidget);
      expect(find.text("Disabled"), findsOneWidget);
      expect(
        _buttonContainerColor(tester, "Disabled"),
        ColorTokens.light.fillDark,
      );
      expect(_textColor(tester, "No callback"), ColorTokens.light.textLightest);
      expect(_textColor(tester, "Disabled"), ColorTokens.light.textLightest);
      await tester.tap(find.text("Disabled"));
      await tester.pump();

      expect(tapCount, 0);
    },
  );

  testWidgets("ButtonComponent renders pressed visual state from gesture", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(ButtonComponent(label: "Continue", onTap: () {})),
    );

    expect(_containerColor(tester), const Color(0xFF08C225));

    final gesture = await tester.startGesture(
      tester.getCenter(find.text("Continue")),
    );
    await tester.pump();

    expect(_containerColor(tester), const Color(0xFF057C18));

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 140));

    expect(_containerColor(tester), const Color(0xFF08C225));
  });

  testWidgets("Large secondary and link buttons match the catalog layout", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ButtonComponent(
          label: "Cancel",
          variant: ButtonComponentVariant.secondary,
          size: ButtonComponentSize.large,
          onTap: () {},
        ),
      ),
    );

    expect(_containerColor(tester), ColorTokens.light.fillDark);
    expect(_textColor(tester, "Cancel"), ColorTokens.light.textBase);
    expect(tester.getSize(find.byType(AnimatedContainer)).height, 52);

    await tester.pumpWidget(
      _wrap(
        ButtonComponent(
          label: "Forgot password?",
          variant: ButtonComponentVariant.link,
          size: ButtonComponentSize.large,
          onTap: () {},
        ),
      ),
    );

    expect(tester.getSize(find.byType(AnimatedContainer)).height, 52);
  });

  testWidgets("Secondary button states follow Figma fill and text tokens", (
    tester,
  ) async {
    Future<void> pumpSecondary({
      required String label,
      required ComponentApp app,
      Brightness brightness = Brightness.light,
    }) {
      return tester.pumpWidget(
        _wrap(
          ButtonComponent(
            label: label,
            variant: ButtonComponentVariant.secondary,
            size: ButtonComponentSize.large,
            onTap: () {},
          ),
          app: app,
          brightness: brightness,
        ),
      );
    }

    await pumpSecondary(label: "Photos", app: ComponentApp.photos);
    expect(_containerColor(tester), ColorTokens.light.fillDark);
    expect(_textColor(tester, "Photos"), ColorTokens.light.textBase);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.text("Photos")));
    await tester.pumpAndSettle();

    expect(_containerColor(tester), ColorTokens.light.fillDarker);

    final photosGesture = await tester.startGesture(
      tester.getCenter(find.text("Photos")),
    );
    await tester.pump();

    expect(_containerColor(tester), ColorTokens.light.fillDarkest);
    expect(_textColor(tester, "Photos"), ColorTokens.light.textBase);

    await photosGesture.up();
    await tester.pump(const Duration(milliseconds: 140));
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();

    await pumpSecondary(label: "Locker", app: ComponentApp.locker);
    expect(_containerColor(tester), ColorTokens.light.fillDark);
    expect(_textColor(tester, "Locker"), ColorTokens.light.textBase);

    await pumpSecondary(label: "Auth", app: ComponentApp.auth);
    expect(_containerColor(tester), ColorTokens.light.fillDark);
    expect(_textColor(tester, "Auth"), ColorTokens.light.textBase);

    await pumpSecondary(
      label: "Auth dark",
      app: ComponentApp.auth,
      brightness: Brightness.dark,
    );
    expect(_containerColor(tester), ColorTokens.dark.fillDark);
    expect(_textColor(tester, "Auth dark"), ColorTokens.dark.textBase);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text("Auth dark")),
    );
    await tester.pump();

    expect(_containerColor(tester), ColorTokens.dark.fillDarkest);
    expect(_textColor(tester, "Auth dark"), ColorTokens.dark.textBase);

    await gesture.up();
  });

  testWidgets("IconButtonComponent renders Figma size and pressed state", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        IconButtonComponent(
          icon: const Icon(Icons.add),
          variant: IconButtonComponentVariant.primary,
          onTap: () {},
        ),
      ),
    );

    final surfaceFinder = find.byKey(const ValueKey('icon-button-surface'));
    final surface = tester.widget<AnimatedContainer>(surfaceFinder);
    final decoration = surface.decoration! as BoxDecoration;

    expect(tester.getSize(surfaceFinder), const Size(36, 36));
    expect(decoration.color, ColorTokens.light.fillLight);

    final gesture = await tester.startGesture(tester.getCenter(surfaceFinder));
    await tester.pump(const Duration(milliseconds: 200));

    final pressedSurface = tester.widget<AnimatedContainer>(surfaceFinder);
    final pressedDecoration = pressedSurface.decoration! as BoxDecoration;
    expect(pressedDecoration.color, ColorTokens.light.fillDarker);

    await gesture.up();
  });

  testWidgets("IconButtonComponent default variant is secondary", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(IconButtonComponent(icon: const Icon(Icons.add), onTap: () {})),
    );

    expect(_iconButtonColor(tester), Colors.transparent);
  });

  testWidgets("IconButtonComponent calls taps only when enabled", (
    tester,
  ) async {
    var tapCount = 0;

    await tester.pumpWidget(
      _wrap(
        IconButtonComponent(
          icon: const Icon(Icons.add),
          onTap: () => tapCount += 1,
        ),
      ),
    );

    await tester.tap(find.byType(GestureDetector));
    await tester.pump();

    expect(tapCount, 1);
  });

  testWidgets("IconButtonComponent can handle tap down without onTap", (
    tester,
  ) async {
    TapDownDetails? tapDownDetails;

    await tester.pumpWidget(
      _wrap(
        IconButtonComponent(
          icon: const Icon(Icons.add),
          onTapDown: (details) => tapDownDetails = details,
        ),
      ),
    );

    final surfaceFinder = find.byKey(const ValueKey('icon-button-surface'));
    final gesture = await tester.startGesture(tester.getCenter(surfaceFinder));
    await tester.pump();

    expect(tapDownDetails, isNotNull);
    expect(_iconButtonColor(tester), Colors.transparent);

    await gesture.up();
  });

  testWidgets("IconButtonComponent mutes disabled foreground", (tester) async {
    await tester.pumpWidget(
      _wrap(
        const IconButtonComponent(
          icon: Icon(Icons.add),
          variant: IconButtonComponentVariant.primary,
          onTap: null,
        ),
      ),
    );

    final iconTheme = tester.widget<IconTheme>(
      find.descendant(
        of: find.byKey(const ValueKey('icon-button-surface')),
        matching: find.byType(IconTheme),
      ),
    );
    expect(iconTheme.data.color, ColorTokens.light.textLighter);
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

  testWidgets("IconButtonComponent can show success for fast actions", (
    tester,
  ) async {
    var tapCount = 0;

    await tester.pumpWidget(
      _wrap(
        IconButtonComponent(
          icon: const Icon(Icons.add),
          shouldShowSuccessConfirmation: true,
          onTap: () => tapCount += 1,
        ),
      ),
    );

    await tester.tap(find.byType(GestureDetector));
    await tester.pump();

    expect(tapCount, 1);
    expect(find.byKey(const ValueKey('success')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byIcon(Icons.add), findsNothing);
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

Color _containerColor(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find.byType(AnimatedContainer),
  );
  return (container.decoration! as BoxDecoration).color!;
}

Color _buttonContainerColor(WidgetTester tester, String label) {
  final container = tester.widget<AnimatedContainer>(
    find.ancestor(
      of: find.text(label),
      matching: find.byType(AnimatedContainer),
    ),
  );
  return (container.decoration! as BoxDecoration).color!;
}

Color _iconButtonColor(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find.byKey(const ValueKey('icon-button-surface')),
  );
  return (container.decoration! as BoxDecoration).color!;
}

Color _textColor(WidgetTester tester, String label) {
  final text = tester.widget<Text>(find.text(label));
  return text.style!.color!;
}

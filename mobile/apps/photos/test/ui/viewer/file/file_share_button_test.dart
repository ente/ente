import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_strings/l10n/strings_localizations_en.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter/semantics.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/viewer/file/file_share_button.dart";

const _dockKey = ValueKey("file-share-dock");
const _fileKey = ValueKey("file-share-file");
const _linkKey = ValueKey("file-share-link");

class _LongStrings extends StringsLocalizationsEn {
  @override
  String get sendVideo => "Eine Kopie dieses Videos an eine andere App senden";
  @override
  String get sendLink =>
      "Einen Link zu diesem Video mit anderen Personen teilen";
}

class _LongStringsDelegate extends LocalizationsDelegate<StringsLocalizations> {
  const _LongStringsDelegate();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<StringsLocalizations> load(Locale locale) =>
      SynchronousFuture(_LongStrings());
  @override
  bool shouldReload(_LongStringsDelegate old) => false;
}

Future<void> _pumpShareButton(
  WidgetTester tester, {
  required VoidCallback onSendFile,
  required VoidCallback onSendLink,
  VoidCallback? onBackgroundTap,
  bool canSendLink = true,
  bool isVideo = false,
  double textScale = 1,
  bool longLabels = false,
  bool reduceMotion = false,
  TextDirection direction = TextDirection.ltr,
  Size size = const Size(390, 844),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ComponentTheme.darkTheme(),
      localizationsDelegates: [
        if (longLabels) const _LongStringsDelegate(),
        ...StringsLocalizations.localizationsDelegates,
      ],
      supportedLocales: const [Locale("en")],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: Directionality(textDirection: direction, child: child!),
      ),
      home: Scaffold(
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onBackgroundTap,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: FileShareButton(
                canSendLink: canSendLink,
                isVideo: isVideo,
                onSendFile: onSendFile,
                onSendLink: onSendLink,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader("packages/ente_components/Inter")
      ..addFont(
        rootBundle.load("packages/ente_components/fonts/Inter-Medium.ttf"),
      );
    await font.load();
  });

  testWidgets("dock opens without overshoot and shares only after closing", (
    tester,
  ) async {
    var filesSent = 0;
    var linksSent = 0;
    await _pumpShareButton(
      tester,
      onSendFile: () {
        expect(find.byKey(_dockKey), findsNothing);
        filesSent++;
      },
      onSendLink: () {
        expect(find.byKey(_dockKey), findsNothing);
        linksSent++;
      },
    );

    final button = find.byType(FileShareButton);
    final buttonRect = tester.getRect(button);
    await tester.tap(button);
    await tester.pump();
    final openingRect = tester.getRect(find.byKey(_dockKey));
    await tester.pump(const Duration(milliseconds: 40));
    final risingRect = tester.getRect(find.byKey(_dockKey));
    expect(risingRect.width, greaterThan(openingRect.width));
    expect(risingRect.bottom, lessThan(openingRect.bottom));
    expect(tester.getRect(button), buttonRect);
    await tester.pump(const Duration(milliseconds: 69));
    final approachingRect = tester.getRect(find.byKey(_dockKey));
    await tester.pumpAndSettle();
    final settledRect = tester.getRect(find.byKey(_dockKey));
    expect(approachingRect.width, greaterThanOrEqualTo(risingRect.width));
    expect(approachingRect.width, lessThanOrEqualTo(settledRect.width));
    expect(approachingRect.bottom, lessThanOrEqualTo(risingRect.bottom));
    expect(approachingRect.bottom, greaterThanOrEqualTo(settledRect.bottom));
    final fileRect = tester.getRect(find.byKey(_fileKey));
    final linkRect = tester.getRect(find.byKey(_linkKey));
    expect(linkRect.bottom, lessThan(buttonRect.top));
    expect(fileRect.center.dy, linkRect.center.dy);
    expect(fileRect.size, linkRect.size);
    expect(fileRect.width, lessThan(390 * 0.35));
    expect(tester.getRect(find.byKey(_dockKey)).width, lessThan(390 * 0.7));
    expect(fileRect.height, greaterThanOrEqualTo(kMinInteractiveDimension));

    await tester.binding.setSurfaceSize(const Size(844, 390));
    await tester.pumpAndSettle();
    final rotatedButton = tester.getRect(button);
    final rotatedDock = tester.getRect(find.byKey(_dockKey));
    expect(rotatedDock.bottom, lessThan(rotatedButton.top));
    expect(rotatedDock.center.dx, closeTo(rotatedButton.center.dx, 1));
    expect(rotatedDock.width, closeTo(settledRect.width, 1));

    await tester.tap(find.text("Send photo"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(filesSent, 0);
    await tester.pumpAndSettle();
    expect(filesSent, 1);
    expect(linksSent, 0);

    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Send link"));
    await tester.pumpAndSettle();
    expect(filesSent, 1);
    expect(linksSent, 1);
  });

  testWidgets("dismissal cancels without sharing or activating the viewer", (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var actions = 0;
    var backgroundTaps = 0;
    await _pumpShareButton(
      tester,
      onSendFile: () => actions++,
      onSendLink: () => actions++,
      onBackgroundTap: () => backgroundTaps++,
    );
    final button = find.byType(FileShareButton);
    final anchor = tester.getCenter(button);
    for (final cancel in <Future<void> Function()>[
      () => tester.tapAt(const Offset(20, 20)),
      () => tester.tapAt(anchor),
      () async {
        await tester.binding.handlePopRoute();
      },
      () => tester.sendKeyEvent(LogicalKeyboardKey.escape),
      () async {
        tester.semantics.dismiss(
          find.semantics.byAction(SemanticsAction.dismiss),
        );
      },
    ]) {
      await tester.tap(button);
      await tester.pumpAndSettle();
      await cancel();
      await tester.pumpAndSettle();
      expect(find.byKey(_dockKey), findsNothing);
      expect(actions, 0);
      expect(backgroundTaps, 0);
    }

    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    final openingRect = tester.getRect(find.byKey(_dockKey));
    await tester.tapAt(anchor);
    await tester.pump();
    expect(tester.getRect(find.byKey(_dockKey)), openingRect);
    await tester.pumpAndSettle();
    expect(find.byKey(_dockKey), findsNothing);
    expect(actions, 0);
    expect(backgroundTaps, 0);
    semantics.dispose();
  });

  testWidgets("Reduce Motion fades without shifting or scaling the dock", (
    tester,
  ) async {
    await _pumpShareButton(
      tester,
      reduceMotion: true,
      onSendFile: () {},
      onSendLink: () {},
    );
    await tester.tap(find.byType(FileShareButton));
    await tester.pump();
    final openingRect = tester.getRect(find.byKey(_dockKey));
    await tester.pump(const Duration(milliseconds: 60));
    final fade = find.ancestor(
      of: find.byKey(_dockKey),
      matching: find.byType(FadeTransition),
    );
    expect(
      tester.widget<FadeTransition>(fade).opacity.value,
      allOf(greaterThan(0), lessThan(1)),
    );
    expect(tester.getRect(find.byKey(_dockKey)), openingRect);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(_dockKey)), openingRect);
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getRect(find.byKey(_dockKey)), openingRect);
    await tester.pumpAndSettle();
    expect(find.byKey(_dockKey), findsNothing);
  });

  testWidgets("shares directly when a link is unavailable", (tester) async {
    var filesSent = 0;
    var linksSent = 0;
    await _pumpShareButton(
      tester,
      canSendLink: false,
      onSendFile: () => filesSent++,
      onSendLink: () => linksSent++,
    );
    await tester.tap(find.byType(FileShareButton));
    await tester.pumpAndSettle();
    expect(filesSent, 1);
    expect(linksSent, 0);
    expect(find.byKey(_dockKey), findsNothing);
  });

  testWidgets("long labels stack, wrap, and stay usable at large text in RTL", (
    tester,
  ) async {
    var filesSent = 0;
    var linksSent = 0;
    await _pumpShareButton(
      tester,
      isVideo: true,
      longLabels: true,
      size: const Size(320, 568),
      onSendFile: () => filesSent++,
      onSendLink: () => linksSent++,
    );
    await tester.tap(find.byType(FileShareButton));
    await tester.pumpAndSettle();
    final wrappedFile = tester.getRect(find.byKey(_fileKey));
    final wrappedLink = tester.getRect(find.byKey(_linkKey));
    expect(wrappedFile.size, wrappedLink.size);
    expect(wrappedFile.center.dy, wrappedLink.center.dy);
    expect(wrappedFile.width, closeTo(320 * 0.35, 0.01));
    expect(
      tester.getSize(find.text(_LongStrings().sendVideo)).height,
      greaterThan(20),
    );
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await _pumpShareButton(
      tester,
      isVideo: true,
      longLabels: true,
      textScale: 3,
      direction: TextDirection.rtl,
      size: const Size(320, 568),
      onSendFile: () => filesSent++,
      onSendLink: () => linksSent++,
    );
    final button = find.byType(FileShareButton);
    await tester.tap(button);
    await tester.pumpAndSettle();
    final fileRect = tester.getRect(find.byKey(_fileKey));
    final linkRect = tester.getRect(find.byKey(_linkKey));
    expect(find.text(_LongStrings().sendVideo), findsOneWidget);
    expect(linkRect.top, greaterThanOrEqualTo(fileRect.bottom));
    final dockRect = tester.getRect(find.byKey(_dockKey));
    expect(dockRect.left, greaterThanOrEqualTo(16));
    expect(dockRect.right, lessThanOrEqualTo(304));
    expect(dockRect.top, greaterThanOrEqualTo(12));
    expect(dockRect.bottom, lessThan(tester.getRect(button).top));
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(_linkKey),
      100,
      scrollable: find.descendant(
        of: find.byKey(_dockKey),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.text(_LongStrings().sendLink));
    await tester.pumpAndSettle();
    expect(linksSent, 1);
    expect(filesSent, 0);
  });
}

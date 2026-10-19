import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_strings/l10n/strings_localizations_en.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/viewer/file/file_share_button.dart";

const _sheetKey = ValueKey("file-share-sheet");
const _linkKey = ValueKey("file-share-link");

class _LongStrings extends StringsLocalizationsEn {
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
  double textScale = 1,
  bool longLabels = false,
  TextDirection direction = TextDirection.ltr,
  Size size = const Size(390, 844),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ComponentTheme.darkTheme().copyWith(platform: TargetPlatform.iOS),
      localizationsDelegates: [
        if (longLabels) const _LongStringsDelegate(),
        ...StringsLocalizations.localizationsDelegates,
      ],
      supportedLocales: const [Locale("en")],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
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

  testWidgets("shares the selected action only after the sheet is removed", (
    tester,
  ) async {
    var filesSent = 0;
    var linksSent = 0;
    await _pumpShareButton(
      tester,
      onSendFile: () {
        expect(find.byKey(_sheetKey), findsNothing);
        filesSent++;
      },
      onSendLink: () {
        expect(find.byKey(_sheetKey), findsNothing);
        linksSent++;
      },
    );
    final button = find.byType(FileShareButton);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheetComponent), findsOneWidget);
    expect(find.text("Send a copy"), findsOneWidget);
    expect(find.text("Send the file to another app"), findsOneWidget);
    expect(find.text("Share a link to this item"), findsOneWidget);
    await tester.tap(find.text("Send a copy"));
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

  testWidgets("closing cancels without sharing or activating the viewer", (
    tester,
  ) async {
    var actions = 0;
    var backgroundTaps = 0;
    await _pumpShareButton(
      tester,
      onSendFile: () => actions++,
      onSendLink: () => actions++,
      onBackgroundTap: () => backgroundTaps++,
    );
    for (final cancel in <Future<void> Function()>[
      () => tester.tap(find.byTooltip("Close")),
      () => tester.tapAt(const Offset(20, 20)),
    ]) {
      await tester.tap(find.byType(FileShareButton));
      await tester.pumpAndSettle();
      await cancel();
      await tester.pumpAndSettle();
      expect(find.byKey(_sheetKey), findsNothing);
      expect(actions, 0);
      expect(backgroundTaps, 0);
    }
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
    expect(find.byKey(_sheetKey), findsNothing);
  });

  testWidgets(
    "choices remain reachable with large text in a narrow RTL sheet",
    (tester) async {
      var linksSent = 0;
      await _pumpShareButton(
        tester,
        longLabels: true,
        textScale: 3,
        direction: TextDirection.rtl,
        size: const Size(320, 568),
        onSendFile: () {},
        onSendLink: () => linksSent++,
      );
      await tester.tap(find.byType(FileShareButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(_linkKey),
        100,
        scrollable: find.descendant(
          of: find.byKey(_sheetKey),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text(_LongStrings().sendLink));
      await tester.pumpAndSettle();
      expect(linksSent, 1);
    },
  );
}

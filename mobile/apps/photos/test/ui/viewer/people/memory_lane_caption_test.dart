import "package:ente_strings/ente_strings.dart";
import "package:ente_strings/l10n/strings_localizations_en.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:intl/intl.dart";
import "package:photos/ui/viewer/people/memory_lane_caption.dart";

const _name = MemoryLaneCaption.namePlaceholder;
const _time = MemoryLaneCaption.timePlaceholder;

void main() {
  testWidgets("glides through digit widths and aligns the caption baselines", (
    tester,
  ) async {
    await _pump(tester, value: 10);
    final name = find.byKey(const ValueKey("memory-lane-caption-name-0"));
    final unit = find.byKey(const ValueKey("memory-lane-caption-literal-2"));
    final start = tester.getTopLeft(name);
    expect(tester.getTopLeft(unit).dy, closeTo(start.dy, 0.01));
    await _pump(tester, value: 9);
    expect(tester.getTopLeft(name).dx, closeTo(start.dx, 0.01));
    await tester.pump(const Duration(milliseconds: 150));
    final middle = tester.getTopLeft(name).dx;
    await tester.pumpAndSettle();
    final end = tester.getTopLeft(name).dx;
    expect(middle, greaterThan(start.dx));
    expect(middle, lessThan(end));
    expect(
      tester.getTopLeft(unit).dy,
      closeTo(tester.getTopLeft(name).dy, 0.01),
    );
    expect(
      tester.widget<Text>(find.text("9")).style!.fontSize,
      closeTo(32 * 0.88, 0.001),
    );

    await _pump(tester, value: null);
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      find.byKey(const ValueKey("memory-lane-caption-old-time-0")),
      findsOneWidget,
    );
    await _pump(tester, value: 1);
    await tester.pump(const Duration(milliseconds: 100));
    await _pump(tester, value: null);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey("memory-lane-caption-old-time-0")),
      findsNothing,
    );
    expect(find.bySemanticsLabel("Ashil now"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    "keeps translated order and whole words through the now handoff",
    (tester) async {
      for (final (language, word, numeric, present, name) in [
        ("ar", "الآن", "$_name قبل $_time أعوام", "$_time $_name", "Ashil"),
        ("ja", "今", "$_time年前の$_name", "$_timeの$_name", "アシル"),
      ]) {
        await _pump(
          tester,
          value: 12,
          language: language,
          word: word,
          caption: numeric,
          name: name,
        );
        await tester.pumpAndSettle();
        final formatted = NumberFormat.decimalPattern(language).format(12);
        expect(
          find.bySemanticsLabel(
            numeric.replaceAll(_name, name).replaceAll(_time, formatted),
          ),
          findsOneWidget,
        );
        await _pump(
          tester,
          value: null,
          language: language,
          word: word,
          caption: present,
          name: name,
        );
        await tester.pumpAndSettle();
        final nameRect = tester.getRect(
          find.byKey(const ValueKey("memory-lane-caption-name-0")),
        );
        final timeRect = tester.getRect(
          find.byKey(const ValueKey("memory-lane-caption-time-0")),
        );
        expect(
          language == "ar"
              ? nameRect.left < timeRect.left
              : timeRect.left < nameRect.left,
          isTrue,
        );
        expect(
          find.bySemanticsLabel(
            present.replaceAll(_name, name).replaceAll(_time, word),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets("large captions fit and reduced motion completes immediately", (
    tester,
  ) async {
    for (final name in ["", "A long multilingual name 👨‍👩‍👧‍👦 " * 8]) {
      await _pump(
        tester,
        value: 12,
        width: 170,
        scale: 2,
        reduceMotion: true,
        name: name,
      );
      await _pump(
        tester,
        value: null,
        width: 170,
        scale: 2,
        reduceMotion: true,
        name: name,
      );
      expect(
        find.byKey(const ValueKey("memory-lane-caption-old-time-0")),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel(name.isEmpty ? "now" : "$name now"),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byType(MemoryLaneCaption)).width,
        lessThanOrEqualTo(170),
      );
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    }
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required int? value,
  String? caption,
  String name = "Ashil",
  String language = "en",
  String word = "now",
  double width = 320,
  double scale = 1,
  bool reduceMotion = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      supportedLocales: StringsLocalizations.supportedLocales,
      localizationsDelegates: [
        _StringsDelegate(language, word),
        ...StringsLocalizations.localizationsDelegates,
      ],
      home: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(scale),
          disableAnimations: reduceMotion,
        ),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: MemoryLaneCaption(
                name: name,
                value: value,
                caption:
                    caption ??
                    (value == null
                        ? "$_name $_time"
                        : "$_name $_time years ago"),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _StringsDelegate extends LocalizationsDelegate<StringsLocalizations> {
  const _StringsDelegate(this.language, this.word);
  final String language;
  final String word;
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<StringsLocalizations> load(Locale locale) =>
      SynchronousFuture(_Strings(language, word));
  @override
  bool shouldReload(_StringsDelegate old) =>
      old.language != language || old.word != word;
}

class _Strings extends StringsLocalizationsEn {
  _Strings(super.locale, this.word);
  final String word;
  @override
  String get memoryLaneNow => word;
}

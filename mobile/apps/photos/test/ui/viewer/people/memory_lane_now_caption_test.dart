import "package:ente_strings/ente_strings.dart";
import "package:ente_strings/l10n/strings_localizations_en.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/viewer/people/memory_lane_now_caption.dart";

void main() {
  testWidgets("styles only the localized time word in translated order", (
    tester,
  ) async {
    for (final (locale, name, word, beforeName, separator) in [
      (const Locale("en"), "Snow now", "now", false, " "),
      (const Locale("ar"), "Ashil", "الآن", true, " "),
      (const Locale("ja"), "アシル", "今", true, "の"),
    ]) {
      final strings = _CaptionStrings(
        locale,
        word,
        beforeName: beforeName,
        separator: separator,
      );
      await _pumpCaption(tester, name: name, strings: strings);
      final text = tester.widget<Text>(find.byType(Text));
      final span = text.textSpan! as TextSpan;
      expect(
        span.toPlainText(),
        strings.memoryLaneCaptionNow(name: name, now: word),
      );
      final timeSpan = span.children!.cast<TextSpan>().singleWhere(
        (child) => child.style != null,
      );
      expect(timeSpan.text, word);
      expect(timeSpan.style!.fontFamily, "packages/ente_components/Gochi Hand");
      expect(timeSpan.style!.fontFamilyFallback, [
        "packages/ente_components/Inter",
      ]);
      expect(timeSpan.style!.fontSize, 22);
      expect(timeSpan.style!.fontWeight, FontWeight.w400);
      expect(timeSpan.style!.color, darkTheme.textTheme.h2Bold.color);
      expect(text.style, darkTheme.textTheme.bodyMuted);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.byType(RichText),
      );
      expect(
        paragraph.textDirection,
        locale.languageCode == "ar" ? TextDirection.rtl : TextDirection.ltr,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets("scales captions and handles empty or long names", (
    tester,
  ) async {
    final english = _CaptionStrings(const Locale("en"), "now");
    final japanese = _CaptionStrings(
      const Locale("ja"),
      "今",
      beforeName: true,
      separator: "の",
    );
    for (final (name, strings) in [
      ("", english),
      ("", japanese),
      ("A very long person's name " * 10, english),
    ]) {
      await _pumpCaption(
        tester,
        name: name,
        strings: strings,
        width: 170,
        textScaler: const TextScaler.linear(2),
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.byType(RichText),
      );
      expect(paragraph.textScaler.scale(22), 44);
      expect(
        paragraph.text.toPlainText(),
        name.isEmpty
            ? strings.memoryLaneNow
            : strings.memoryLaneCaptionNow(
                name: name,
                now: strings.memoryLaneNow,
              ),
      );
      expect(paragraph.didExceedMaxLines, name.isNotEmpty);
      expect(paragraph.size.width, lessThanOrEqualTo(170));
      expect(tester.takeException(), isNull);
    }
  });
}

Future<void> _pumpCaption(
  WidgetTester tester, {
  required String name,
  required _CaptionStrings strings,
  double width = 320,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: strings.locale,
      supportedLocales: StringsLocalizations.supportedLocales,
      localizationsDelegates: [
        _CaptionStringsDelegate(strings),
        ...StringsLocalizations.localizationsDelegates,
      ],
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: textScaler),
          child: Center(
            child: SizedBox(
              width: width,
              child: MemoryLaneNowCaption(name: name),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _CaptionStringsDelegate
    extends LocalizationsDelegate<StringsLocalizations> {
  const _CaptionStringsDelegate(this.strings);

  final _CaptionStrings strings;

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<StringsLocalizations> load(Locale locale) =>
      SynchronousFuture(strings);

  @override
  bool shouldReload(_CaptionStringsDelegate old) => old.strings != strings;
}

class _CaptionStrings extends StringsLocalizationsEn {
  _CaptionStrings(
    this.locale,
    this.word, {
    this.beforeName = false,
    this.separator = " ",
  }) : super(locale.toLanguageTag());

  final Locale locale;
  final String word;
  final bool beforeName;
  final String separator;

  @override
  String get memoryLaneNow => word;

  @override
  String memoryLaneCaptionNow({required String name, required String now}) =>
      beforeName ? "$now$separator$name" : "$name$separator$now";
}

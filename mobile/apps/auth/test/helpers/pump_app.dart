import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_localizations/flutter_localizations.dart";
import "package:flutter_test/flutter_test.dart";

extension PumpApp on WidgetTester {
  Future<void> pumpApp(Widget widget) {
    return pumpWidget(
      MaterialApp(
        localizationsDelegates: const [GlobalMaterialLocalizations.delegate],
        supportedLocales: StringsLocalizations.supportedLocales,
        home: widget,
      ),
    );
  }
}

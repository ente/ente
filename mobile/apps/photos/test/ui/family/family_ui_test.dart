import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photos/ente_theme_data.dart';
import 'package:photos/ui/family/family_ui.dart';

void main() {
  testWidgets('keeps titled form content vertically bounded', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        home: const FamilyPageScaffold(
          title: 'Family form',
          child: Column(
            children: [
              Expanded(child: SizedBox.expand()),
              SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Family form'), findsOneWidget);
  });
}

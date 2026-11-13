import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/common/date_input.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('supports typed optional dates', (tester) async {
    DateTime? selectedDate;
    bool? isValid;
    await tester.pumpWidget(
      MaterialApp(
        theme: ComponentTheme.lightTheme(),
        home: Scaffold(
          body: DatePickerField(
            initialValue: '2000-07-14',
            firstDate: DateTime(100),
            lastDate: DateTime(2100),
            isRequired: false,
            onChanged: (date) => selectedDate = date,
            onValidityChanged: (value) => isValid = value,
          ),
        ),
      ),
    );

    final field = find.byType(TextField);
    expect(tester.widget<TextField>(field).controller!.text, '07/14/2000');

    await tester.enterText(field, '12/31/2000');
    expect(selectedDate, DateTime(2000, 12, 31));
    expect(isValid, isTrue);

    await tester.enterText(field, '02/30/2000');
    await tester.pump();
    expect(selectedDate, DateTime(2000, 12, 31));
    expect(isValid, isFalse);
    expect(find.text('MM/DD/YYYY'), findsOneWidget);

    await tester.enterText(field, '');
    await tester.pump();
    expect(selectedDate, isNull);
    expect(isValid, isTrue);
    expect(find.text('MM/DD/YYYY'), findsNothing);
  });

  testWidgets('opens with a stale maximum date', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ComponentTheme.lightTheme(),
        home: Scaffold(
          body: DatePickerField(
            firstDate: DateTime(100),
            lastDate: DateUtils.dateOnly(
              DateTime.now().subtract(const Duration(days: 1)),
            ),
            isRequired: false,
          ),
        ),
      ),
    );

    final input = find.byType(TextInputComponent);
    final inputRect = tester.getRect(input);
    await tester.tapAt(Offset(inputRect.right - 24, inputRect.center.dy));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('opens with an out-of-range initial date', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ComponentTheme.lightTheme(),
        home: Scaffold(
          body: DatePickerField(
            initialValue: '2200-01-01',
            firstDate: DateTime(100),
            lastDate: DateTime.now(),
            isRequired: false,
          ),
        ),
      ),
    );

    final input = find.byType(TextInputComponent);
    final inputRect = tester.getRect(input);
    await tester.tapAt(Offset(inputRect.right - 24, inputRect.center.dy));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
  });
}

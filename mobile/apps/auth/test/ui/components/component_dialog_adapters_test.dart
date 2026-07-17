import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/ui/components/action_sheet_widget.dart';
import 'package:ente_auth/ui/components/buttons/button_widget.dart';
import 'package:ente_auth/ui/components/dialog_widget.dart';
import 'package:ente_auth/ui/components/models/button_result.dart';
import 'package:ente_auth/ui/components/models/button_type.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('legacy action sheets render with Ente components', (
    tester,
  ) async {
    await _pumpLauncher(
      tester,
      (context) => showActionSheet(
        context: context,
        title: 'Trash code?',
        body: 'The code can be restored later.',
        buttons: const [
          ButtonWidget(
            buttonType: ButtonType.critical,
            labelText: 'Trash',
            isInAlert: true,
            buttonAction: ButtonAction.first,
          ),
          ButtonWidget(
            buttonType: ButtonType.secondary,
            labelText: 'Cancel',
            isInAlert: true,
            buttonAction: ButtonAction.cancel,
          ),
        ],
      ),
    );

    await _openLauncher(tester);

    expect(find.byType(BottomSheetComponent), findsOneWidget);
    expect(find.byType(ButtonWidget), findsNothing);
    expect(find.text('Trash code?'), findsOneWidget);
    expect(find.text('The code can be restored later.'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(find.byTooltip('Close'), findsOneWidget);
    final button = tester.widget<ButtonComponent>(
      find.widgetWithText(ButtonComponent, 'Trash'),
    );
    expect(button.variant, ButtonComponentVariant.critical);
  });

  testWidgets('legacy dialog returns its component button action', (
    tester,
  ) async {
    ButtonResult? result;
    await _pumpLauncher(tester, (context) async {
      result = await showDialogWidget(
        context: context,
        title: 'Continue?',
        buttons: const [
          ButtonWidget(
            buttonType: ButtonType.neutral,
            labelText: 'Continue',
            isInAlert: true,
            buttonAction: ButtonAction.first,
          ),
        ],
      );
    });

    await _openLauncher(tester);
    expect(find.byType(BottomSheetComponent), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(result?.action, ButtonAction.first);
    expect(find.byType(BottomSheetComponent), findsNothing);
  });

  testWidgets('text input dialogs use component input and submit button', (
    tester,
  ) async {
    String? submittedValue;
    await _pumpLauncher(
      tester,
      (context) => showTextInputDialog(
        context,
        title: 'Create tag',
        submitButtonLabel: 'Create',
        onSubmit: (value) async => submittedValue = value,
      ),
    );

    await _openLauncher(tester);

    expect(find.byType(BottomSheetComponent), findsOneWidget);
    expect(find.byType(TextInputComponent), findsOneWidget);
    expect(
      tester
          .widget<ButtonComponent>(
            find.widgetWithText(ButtonComponent, 'Create'),
          )
          .isDisabled,
      isTrue,
    );

    await tester.enterText(find.byType(TextField), 'Work');
    await tester.pump();
    expect(
      tester
          .widget<ButtonComponent>(
            find.widgetWithText(ButtonComponent, 'Create'),
          )
          .isDisabled,
      isFalse,
    );

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(submittedValue, 'Work');
    expect(find.byType(BottomSheetComponent), findsNothing);
  });
}

Future<void> _pumpLauncher(
  WidgetTester tester,
  Future<dynamic> Function(BuildContext context) onOpen,
) {
  return tester.pumpWidget(
    MaterialApp(
      theme: ComponentTheme.lightTheme(app: ComponentApp.auth),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => onOpen(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openLauncher(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

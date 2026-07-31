import "package:ente_base/typedefs.dart";
import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";

Future<dynamic> showTextInputSheet(
  BuildContext context, {
  required String title,
  required String hintText,
  required String submitButtonLabel,
  required FutureVoidCallbackParamStr onSubmit,
  String? initialValue,
  TextCapitalization textCapitalization = TextCapitalization.words,
  int? maxLength,
  bool isPasswordInput = false,
}) {
  var currentText = initialValue ?? '';
  var isSubmitting = false;

  final canSubmit = ValueNotifier<bool>(currentText.trim().isNotEmpty);

  Future<void> submit(BuildContext sheetContext, String value) async {
    final text = isPasswordInput ? value : value.trim();
    if (text.trim().isEmpty || isSubmitting) {
      return;
    }

    isSubmitting = true;

    try {
      await onSubmit(text);
      if (sheetContext.mounted) {
        Navigator.of(sheetContext).pop();
      }
    } catch (e) {
      isSubmitting = false;
      if (sheetContext.mounted) {
        Navigator.of(sheetContext).pop(e);
      }
    }
  }

  return showBottomSheetComponent<dynamic>(
    context: context,
    builder: (sheetContext) => BottomSheetComponent(
      title: title,
      isKeyboardAware: true,
      content: TextInputComponent(
        initialValue: initialValue,
        hintText: hintText,
        autofocus: true,
        maxLength: maxLength,
        textCapitalization: textCapitalization,
        isPasswordInput: isPasswordInput,
        onChanged: (value) {
          currentText = value;
          canSubmit.value = value.trim().isNotEmpty;
        },
        onSubmit: (value) => submit(sheetContext, value),
      ),
      actions: [
        ValueListenableBuilder<bool>(
          valueListenable: canSubmit,
          builder: (_, enabled, _) => ButtonComponent(
            label: submitButtonLabel,
            onTap: enabled ? () => submit(sheetContext, currentText) : null,
          ),
        ),
      ],
    ),
  );
}

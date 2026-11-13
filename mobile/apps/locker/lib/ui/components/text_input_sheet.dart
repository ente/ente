import "package:ente_base/typedefs.dart";
import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";

Future<dynamic> showTextInputSheet(
  BuildContext context, {
  required String title,
  required String hintText,
  required String submitButtonLabel,
  required FutureVoidCallbackParamStr onSubmit,
  String? Function(String)? validator,
  String? initialValue,
  TextCapitalization textCapitalization = TextCapitalization.words,
  int? maxLength,
  bool isPasswordInput = false,
  bool selectInitialValue = false,
}) async {
  var currentText = initialValue ?? '';
  var isSubmitting = false;

  final canSubmit = ValueNotifier<bool>(currentText.trim().isNotEmpty);
  final validationError = ValueNotifier<String?>(null);
  final controller = selectInitialValue
      ? TextEditingController.fromValue(
          TextEditingValue(
            text: currentText,
            selection: TextSelection(
              baseOffset: 0,
              extentOffset: currentText.length,
            ),
          ),
        )
      : null;

  Future<void> submit(BuildContext sheetContext, String value) async {
    final text = isPasswordInput ? value : value.trim();
    if (text.trim().isEmpty || isSubmitting) {
      return;
    }

    validationError.value = validator?.call(text);
    if (validationError.value != null) return;

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

  final result = await showBottomSheetComponent<dynamic>(
    context: context,
    builder: (sheetContext) => BottomSheetComponent(
      title: title,
      isKeyboardAware: true,
      content: ValueListenableBuilder<String?>(
        valueListenable: validationError,
        builder: (_, error, _) => TextInputComponent(
          controller: controller,
          initialValue: controller == null ? initialValue : null,
          hintText: hintText,
          autofocus: true,
          maxLength: maxLength,
          textCapitalization: textCapitalization,
          isPasswordInput: isPasswordInput,
          message: error,
          messageType: error == null
              ? TextInputComponentMessageType.helper
              : TextInputComponentMessageType.error,
          onChanged: (value) {
            currentText = value;
            canSubmit.value = value.trim().isNotEmpty;
            validationError.value = null;
          },
          onSubmit: (value) => submit(sheetContext, value),
        ),
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
  validationError.dispose();
  controller?.dispose();
  return result;
}

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:ente_base/typedefs.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/components/action_sheet_widget.dart';
import 'package:ente_ui/components/alert_bottom_sheet.dart';
import 'package:ente_ui/components/buttons/button_widget.dart';
import 'package:ente_ui/components/buttons/gradient_button.dart';
import 'package:ente_ui/components/buttons/models/button_result.dart';
import 'package:ente_ui/components/buttons/models/button_type.dart';
import 'package:ente_ui/components/dialog_widget.dart';
import 'package:ente_ui/components/loading_widget.dart';
import 'package:ente_ui/components/progress_dialog.dart';
import 'package:ente_ui/theme/colors.dart';
import 'package:ente_utils/email_util.dart';
import 'package:ente_utils/platform_util.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

typedef DialogBuilder = DialogWidget Function(BuildContext context);

///Will return null if dismissed by tapping outside
Future<ButtonResult?> showErrorDialog(
  BuildContext context,
  String title,
  String? body, {
  bool isDismissable = true,
}) async {
  return showDialogWidget(
    context: context,
    title: title,
    body: body,
    isDismissible: isDismissable,
    buttons: [
      ButtonWidget(
        buttonType: ButtonType.primary,
        labelText: context.strings.contactSupport,
        isInAlert: true,
        buttonAction: ButtonAction.first,
        onTap: () async {
          await sendEmail(context, to: "support@ente.com", body: body);
        },
      ),
      const ButtonWidget(
        buttonType: ButtonType.secondary,
        labelText: "OK",
        isInAlert: true,
        buttonAction: ButtonAction.second,
      ),
    ],
  );
}

String parseErrorForUI(
  BuildContext context,
  String genericError, {
  Object? error,
  bool surfaceError = kDebugMode,
}) {
  try {
    if (error == null) {
      return genericError;
    }
    if (error is DioException) {
      final DioException dioError = error;
      if (dioError.type == DioExceptionType.unknown) {
        if (dioError.error.toString().contains('Failed host lookup')) {
          return context.strings.networkHostLookUpErr;
        } else if (dioError.error.toString().contains('SocketException')) {
          return context.strings.networkConnectionRefusedErr;
        }
      }
    }
    // Only surface raw error details when explicitly allowed and in debug mode.
    if (!surfaceError || !kDebugMode) {
      return genericError;
    }
    String errorInfo = "";
    if (error is DioException) {
      final DioException dioError = error;
      if (dioError.type == DioExceptionType.badResponse) {
        if (dioError.response?.data["code"] != null) {
          errorInfo = "Reason: ${dioError.response!.data["code"]}";
        } else {
          errorInfo = "Reason: ${dioError.response!.data.toString()}";
        }
      } else if (dioError.type == DioExceptionType.badCertificate) {
        errorInfo = "Reason: ${dioError.error.toString()}";
      } else {
        errorInfo = "Reason: ${dioError.type.toString()}";
      }
    } else {
      if (kDebugMode) {
        errorInfo = error.toString();
      } else {
        errorInfo = error.toString().split('Source stack')[0];
      }
    }
    if (errorInfo.isNotEmpty) {
      return "$genericError\n\n$errorInfo";
    }
    return genericError;
  } catch (e) {
    return genericError;
  }
}

///Will return null if dismissed by tapping outside
Future<ButtonResult?> showGenericErrorDialog({
  required BuildContext context,
  bool isDismissible = true,
  required Object? error,
}) async {
  String errorBody = parseErrorForUI(
    context,
    context.strings.itLooksLikeSomethingWentWrongPleaseRetryAfterSome,
    error: error,
  );
  bool isWindowCertError = false;
  if (Platform.isWindows &&
      error != null &&
      error.toString().contains("CERTIFICATE_VERIFY_FAILED")) {
    isWindowCertError = true;
    errorBody =
        "Certificate verification failed. Please update your system certificates, & restart the app. If the issue persists, please contact support.";
  }

  return showDialogWidget(
    context: context,
    title: context.strings.error,
    icon: Icons.error_outline_outlined,
    body: errorBody,
    isDismissible: isDismissible,
    buttons: [
      ButtonWidget(
        buttonType: ButtonType.primary,
        labelText: context.strings.ok,
        buttonAction: ButtonAction.first,
        isInAlert: true,
      ),
      if (isWindowCertError)
        ButtonWidget(
          buttonType: ButtonType.neutral,
          labelText: 'Update Certificates',
          buttonAction: ButtonAction.third,
          isInAlert: true,
          onTap: () async {
            await PlatformUtil.openWebView(
              context,
              context.strings.faq,
              "https://ente.com/help/auth/troubleshooting/windows-login",
            );
          },
        ),
      ButtonWidget(
        buttonType: ButtonType.secondary,
        labelText: context.strings.contactSupport,
        buttonAction: ButtonAction.second,
        onTap: () async {
          await sendLogs(context, "support@ente.com", postShare: () {});
        },
      ),
    ],
  );
}

Future<void> showGenericErrorBottomSheet({
  required BuildContext context,
  required Object? error,
}) async {
  final errorBody = parseErrorForUI(
    context,
    context.strings.itLooksLikeSomethingWentWrongPleaseRetryAfterSome,
    error: error,
  );
  await showAlertBottomSheet(
    context,
    title: context.strings.error,
    message: errorBody,
    assetPath: 'assets/warning-grey.png',
    buttons: [
      GradientButton(
        text: context.strings.contactSupport,
        onTap: () async {
          await sendLogs(context, "support@ente.com", postShare: () {});
        },
      ),
    ],
  );
}

DialogWidget choiceDialog({
  required String title,
  String? body,
  required String firstButtonLabel,
  String secondButtonLabel = "Cancel",
  ButtonType firstButtonType = ButtonType.neutral,
  ButtonType secondButtonType = ButtonType.secondary,
  ButtonAction firstButtonAction = ButtonAction.first,
  ButtonAction secondButtonAction = ButtonAction.cancel,
  FutureVoidCallback? firstButtonOnTap,
  FutureVoidCallback? secondButtonOnTap,
  bool isCritical = false,
  IconData? icon,
}) {
  final buttons = [
    ButtonWidget(
      buttonType: isCritical ? ButtonType.critical : firstButtonType,
      labelText: firstButtonLabel,
      isInAlert: true,
      onTap: firstButtonOnTap,
      buttonAction: firstButtonAction,
    ),
    ButtonWidget(
      buttonType: secondButtonType,
      labelText: secondButtonLabel,
      isInAlert: true,
      onTap: secondButtonOnTap,
      buttonAction: secondButtonAction,
    ),
  ];

  return DialogWidget(title: title, body: body, buttons: buttons, icon: icon);
}

///Will return null if dismissed by tapping outside
Future<ButtonResult?> showChoiceDialog(
  BuildContext context, {
  required String title,
  String? body,
  required String firstButtonLabel,
  String? secondButtonLabel = "Cancel",
  ButtonType firstButtonType = ButtonType.neutral,
  ButtonType secondButtonType = ButtonType.secondary,
  ButtonAction firstButtonAction = ButtonAction.first,
  ButtonAction secondButtonAction = ButtonAction.cancel,
  FutureVoidCallback? firstButtonOnTap,
  FutureVoidCallback? secondButtonOnTap,
  bool isCritical = false,
  IconData? icon,
  bool isDismissible = true,
}) async {
  final buttons = [
    ButtonWidget(
      buttonType: isCritical ? ButtonType.critical : firstButtonType,
      labelText: firstButtonLabel,
      isInAlert: true,
      onTap: firstButtonOnTap,
      buttonAction: firstButtonAction,
    ),
    if (secondButtonLabel != null)
      ButtonWidget(
        buttonType: secondButtonType,
        labelText: secondButtonLabel,
        isInAlert: true,
        onTap: secondButtonOnTap,
        buttonAction: secondButtonAction,
      ),
  ];
  return showDialogWidget(
    context: context,
    title: title,
    body: body,
    buttons: buttons,
    icon: icon,
    isDismissible: isDismissible,
  );
}

///Will return null if dismissed by tapping outside
Future<ButtonResult?> showChoiceActionSheet(
  BuildContext context, {
  required String title,
  String? body,
  required String firstButtonLabel,
  String secondButtonLabel = "Cancel",
  ButtonType firstButtonType = ButtonType.neutral,
  ButtonType secondButtonType = ButtonType.secondary,
  ButtonAction firstButtonAction = ButtonAction.first,
  ButtonAction secondButtonAction = ButtonAction.cancel,
  FutureVoidCallback? firstButtonOnTap,
  FutureVoidCallback? secondButtonOnTap,
  bool isCritical = false,
  IconData? icon,
  bool isDismissible = true,
}) async {
  final buttons = [
    ButtonWidget(
      buttonType: isCritical ? ButtonType.critical : firstButtonType,
      labelText: firstButtonLabel,
      isInAlert: true,
      onTap: firstButtonOnTap,
      buttonAction: firstButtonAction,
      shouldStickToDarkTheme: true,
    ),
    ButtonWidget(
      buttonType: secondButtonType,
      labelText: secondButtonLabel,
      isInAlert: true,
      onTap: secondButtonOnTap,
      buttonAction: secondButtonAction,
      shouldStickToDarkTheme: true,
    ),
  ];
  return showActionSheet(
    context: context,
    title: title,
    body: body,
    buttons: buttons,
    isDismissible: isDismissible,
  );
}

ProgressDialog createProgressDialog(
  BuildContext context,
  String message, {
  isDismissible = false,
}) {
  final dialog = ProgressDialog(
    context,
    type: ProgressDialogType.normal,
    isDismissible: isDismissible,
    barrierColor: Colors.black12,
  );
  dialog.style(
    message: message,
    messageTextStyle: Theme.of(context).textTheme.labelMedium,
    backgroundColor: Theme.of(context).dialogTheme.backgroundColor,
    progressWidget: const EnteLoadingWidget(),
    borderRadius: 10,
    elevation: 10.0,
    insetAnimCurve: Curves.easeInOut,
  );
  return dialog;
}

//Can return ButtonResult? from ButtonWidget or Exception? from TextInputDialog
Future<dynamic> showTextInputDialog(
  BuildContext context, {
  required String title,
  String? body,
  required String submitButtonLabel,
  IconData? icon,
  String? label,
  String? message,
  String? hintText,
  required FutureVoidCallbackParamStr onSubmit,
  IconData? prefixIcon,
  String? initialValue,
  Alignment? alignMessage,
  int? maxLength,
  bool showOnlyLoadingState = false,
  TextCapitalization textCapitalization = TextCapitalization.none,
  bool alwaysShowSuccessState = false,
  bool isPasswordInput = false,
  bool useRootNavigator = false,
}) {
  return showDialog(
    barrierColor: backdropFaintDark,
    useRootNavigator: useRootNavigator,
    context: context,
    builder: (context) {
      final bottomInset = MediaQuery.of(context).viewInsets.bottom;
      final isKeyboardUp = bottomInset > 100;
      return Material(
        color: Colors.transparent,
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(bottom: isKeyboardUp ? bottomInset : 0),
            child: TextInputDialog(
              title: title,
              message: message,
              label: label,
              body: body,
              icon: icon,
              submitButtonLabel: submitButtonLabel,
              onSubmit: onSubmit,
              hintText: hintText,
              prefixIcon: prefixIcon,
              initialValue: initialValue,
              alignMessage: alignMessage,
              maxLength: maxLength,
              showOnlyLoadingState: showOnlyLoadingState,
              textCapitalization: textCapitalization,
              alwaysShowSuccessState: alwaysShowSuccessState,
              isPasswordInput: isPasswordInput,
            ),
          ),
        ),
      );
    },
  );
}

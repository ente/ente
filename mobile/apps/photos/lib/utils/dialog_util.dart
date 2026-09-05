import "package:dio/dio.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import 'package:ente_ui/components/loading_widget.dart';
import "package:flutter/foundation.dart";
import 'package:flutter/material.dart';
import "package:flutter/services.dart";
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:photos/core/constants.dart';
import 'package:photos/models/button_result.dart';
import 'package:photos/models/typedefs.dart';
import "package:photos/module/download/manager.dart";
import "package:photos/service_locator.dart";
import 'package:photos/ui/common/progress_dialog.dart';
import 'package:photos/ui/components/action_sheet_widget.dart';
import "package:photos/ui/components/alert_bottom_sheet.dart";
import 'package:photos/ui/components/buttons/button_widget.dart';
import "package:photos/ui/components/buttons/button_widget_v2.dart";
import 'package:photos/ui/components/dialog_widget.dart';
import 'package:photos/ui/components/models/button_type.dart';
import "package:photos/utils/email_util.dart";

Future<ButtonResult?> showInfoDialog(
  BuildContext context, {
  String title = "",
  String? body,
  IconData icon = Icons.info_outline_rounded,
  bool isDismissable = true,
}) async {
  return showDialogWidget(
    context: context,
    title: title,
    body: body,
    icon: icon,
    isDismissible: isDismissable,
    buttons: [
      ButtonWidget(
        buttonType: ButtonType.secondary,
        labelText: context.strings.ok,
        isInAlert: true,
        buttonAction: ButtonAction.first,
      ),
    ],
  );
}

Future<ButtonResult?> showErrorDialog(
  BuildContext context,
  String title,
  String? body, {
  bool isDismissable = true,
  bool useRootNavigator = false,
}) async {
  return showDialogWidget(
    context: context,
    title: title,
    body: body,
    isDismissible: isDismissable,
    useRootNavigator: useRootNavigator,
    buttons: [
      ButtonWidget(
        buttonType: ButtonType.secondary,
        labelText: context.strings.ok,
        isInAlert: true,
        buttonAction: ButtonAction.first,
      ),
    ],
  );
}

Future<ButtonResult?> showErrorDialogForException({
  required BuildContext context,
  required Exception exception,
  bool isDismissible = true,
  String apiErrorPrefix = "It looks like something went wrong.",
  String? message,
}) async {
  String errorMessage =
      message ?? context.strings.tempErrorContactSupportIfPersists;
  if (exception is DioException &&
      exception.response != null &&
      exception.response!.data["code"] != null) {
    errorMessage =
        "$apiErrorPrefix\n\nReason: " + exception.response!.data["code"];
  }
  return showDialogWidget(
    context: context,
    title: context.strings.error,
    icon: Icons.error_outline_outlined,
    body: errorMessage,
    isDismissible: isDismissible,
    buttons: [
      ButtonWidget(
        buttonType: ButtonType.secondary,
        labelText: context.strings.ok,
        isInAlert: true,
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
  if (error == null) {
    return genericError;
  }
  if (error.toString() == DownloadManager.applePhotosUnsupportedResourceError) {
    return context.strings.applePhotosUnsupportedResource;
  }
  if (error is DioException) {
    final DioException dioError = error;
    if (dioError.type == DioExceptionType.receiveTimeout ||
        dioError.type == DioExceptionType.connectionError ||
        dioError.type == DioExceptionType.sendTimeout ||
        dioError.type == DioExceptionType.cancel) {
      if (dioError.error.toString().contains('Failed host lookup')) {
        return context.strings.networkHostLookUpErr;
      } else if (dioError.error.toString().contains('SocketException')) {
        return context.strings.networkConnectionRefusedErr;
      }
    }
  }

  if (error is WebResourceError) {
    if (error.type == WebResourceErrorType.HOST_LOOKUP ||
        error.type == WebResourceErrorType.NOT_CONNECTED_TO_INTERNET ||
        error.type == WebResourceErrorType.NETWORK_CONNECTION_LOST ||
        error.type == WebResourceErrorType.TIMEOUT) {
      return context.strings.networkHostLookUpErr;
    } else if (error.type == WebResourceErrorType.CANNOT_CONNECT_TO_HOST ||
        error.type == WebResourceErrorType.SERVER_UNREACHABLE) {
      return context.strings.networkConnectionRefusedErr;
    }
  }

  if (!(flagService.internalUser && kDebugMode)) {
    return genericError;
  }
  String errorInfo = "";
  if (error is DioException) {
    final DioException dioError = error;
    if (dioError.type == DioExceptionType.badResponse) {
      if (dioError.response?.data["code"] != null) {
        errorInfo = "Reason: " + dioError.response!.data["code"];
      } else {
        errorInfo = "Reason: " + dioError.response!.data.toString();
      }
    } else if (dioError.type == DioExceptionType.badCertificate) {
      errorInfo = "Reason: " + dioError.error.toString();
    } else {
      errorInfo = "Reason: " + dioError.type.toString();
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
}

Future<ButtonResult?> showGenericErrorDialog({
  required BuildContext context,
  bool isDismissible = true,
  required Object? error,
}) async {
  final errorBody = parseErrorForUI(
    context,
    context.strings.itLooksLikeSomethingWentWrongPleaseRetryAfterSome,
    error: error,
  );

  final ButtonResult? result = await showDialogWidget(
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
      ButtonWidget(
        buttonType: ButtonType.secondary,
        labelText: context.strings.contactSupport,
        buttonAction: ButtonAction.second,
        onTap: () async {
          await sendLogs(
            context,
            context.strings.contactSupport,
            "support@ente.com",
            postShare: () {},
          );
        },
      ),
    ],
  );
  return result;
}

Future<ButtonResult?> showDownloadDecryptionFailedDialog({
  required BuildContext context,
}) async {
  final title = context.strings.downloadFailed;
  return showDialogWidget(
    context: context,
    title: title,
    icon: Icons.error_outline_outlined,
    body: context.strings.downloadDecryptionFailedMessage,
    buttons: [
      ButtonWidget(
        buttonType: ButtonType.primary,
        labelText: context.strings.contactUs,
        buttonAction: ButtonAction.first,
        isInAlert: true,
        onTap: () async {
          await sendLogs(
            context,
            title,
            supportEmail,
            subject: title,
            postShare: () {},
          );
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
      ButtonWidgetV2(
        buttonType: ButtonTypeV2.secondary,
        labelText: context.strings.contactSupport,
        onTap: () async {
          await sendLogs(
            context,
            context.strings.contactSupport,
            "support@ente.com",
            postShare: () {},
          );
        },
      ),
    ],
  );
}

Future<ButtonResult?> showChoiceDialog(
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
    ),
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

// Legacy; use BottomSheetComponent for new sheets.
Future<ButtonResult?> showChoiceActionSheet(
  BuildContext context, {
  required String title,
  String? body,
  Widget? illustration,
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
    illustration: illustration,
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
  );
  dialog.style(
    message: message,
    messageTextStyle: Theme.of(context).textTheme.bodySmall,
    backgroundColor: Theme.of(context).dialogTheme.backgroundColor,
    progressWidget: const EnteLoadingWidget(),
    borderRadius: 10,
    elevation: 10.0,
    insetAnimCurve: Curves.easeInOut,
  );
  return dialog;
}

// Returns null after submit, ButtonResult on cancel, and Exception on failure.
// Use BottomSheetComponent for new dialogs.
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
  TextEditingController? textEditingController,
  List<TextInputFormatter>? textInputFormatter,
  TextInputType? textInputType,
  bool useRootNavigator = false,
  bool popnavAfterSubmission = true,
}) {
  return showBottomSheetComponent<dynamic>(
    context: context,
    useRootNavigator: useRootNavigator,
    builder: (_) {
      return LegacyTextInputDialog(
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
        textEditingController: textEditingController,
        textInputFormatter: textInputFormatter,
        textInputType: textInputType,
        popnavAfterSubmission: popnavAfterSubmission,
      );
    },
  );
}

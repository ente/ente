import "package:dio/dio.dart";
import "package:ente_components/ente_components.dart";
import "package:flutter/foundation.dart";
import 'package:flutter/material.dart';
import "package:flutter/services.dart";
import "package:photos/generated/l10n.dart";
import 'package:photos/models/button_result.dart';
import 'package:photos/models/typedefs.dart';
import "package:photos/module/download/manager.dart";
import "package:photos/service_locator.dart";
import 'package:photos/ui/common/loading_widget.dart';
import 'package:photos/ui/common/progress_dialog.dart';
import 'package:photos/ui/components/action_sheet_widget.dart';
import "package:photos/ui/components/alert_bottom_sheet.dart";
import 'package:photos/ui/components/buttons/button_widget.dart';
import "package:photos/ui/components/buttons/button_widget_v2.dart";
import 'package:photos/ui/components/dialog_widget.dart';
import 'package:photos/ui/components/models/button_type.dart';
import "package:photos/utils/email_util.dart";

/// Legacy info-dialog helper backed by [showDialogWidget].
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
        labelText: AppLocalizations.of(context).ok,
        isInAlert: true,
        buttonAction: ButtonAction.first,
      ),
    ],
  );
}

/// Legacy error-dialog helper backed by [showDialogWidget].
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
        labelText: AppLocalizations.of(context).ok,
        isInAlert: true,
        buttonAction: ButtonAction.first,
      ),
    ],
  );
}

/// Legacy exception-dialog helper backed by [showDialogWidget].
Future<ButtonResult?> showErrorDialogForException({
  required BuildContext context,
  required Exception exception,
  bool isDismissible = true,
  String apiErrorPrefix = "It looks like something went wrong.",
  String? message,
}) async {
  String errorMessage =
      message ?? AppLocalizations.of(context).tempErrorContactSupportIfPersists;
  if (exception is DioException &&
      exception.response != null &&
      exception.response!.data["code"] != null) {
    errorMessage =
        "$apiErrorPrefix\n\nReason: " + exception.response!.data["code"];
  }
  return showDialogWidget(
    context: context,
    title: AppLocalizations.of(context).error,
    icon: Icons.error_outline_outlined,
    body: errorMessage,
    isDismissible: isDismissible,
    buttons: [
      ButtonWidget(
        buttonType: ButtonType.secondary,
        labelText: AppLocalizations.of(context).ok,
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
    return AppLocalizations.of(context).applePhotosUnsupportedResource;
  }
  if (error is DioException) {
    final DioException dioError = error;
    if (dioError.type == DioExceptionType.receiveTimeout ||
        dioError.type == DioExceptionType.connectionError ||
        dioError.type == DioExceptionType.sendTimeout ||
        dioError.type == DioExceptionType.cancel) {
      if (dioError.error.toString().contains('Failed host lookup')) {
        return AppLocalizations.of(context).networkHostLookUpErr;
      } else if (dioError.error.toString().contains('SocketException')) {
        return AppLocalizations.of(context).networkConnectionRefusedErr;
      }
    }
  }
  // return generic error if the user is not internal and the error is not in debug mode
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

/// Legacy parsed-error dialog helper backed by [showDialogWidget].
Future<ButtonResult?> showGenericErrorDialog({
  required BuildContext context,
  bool isDismissible = true,
  required Object? error,
}) async {
  final errorBody = parseErrorForUI(
    context,
    AppLocalizations.of(
      context,
    ).itLooksLikeSomethingWentWrongPleaseRetryAfterSome,
    error: error,
  );

  final ButtonResult? result = await showDialogWidget(
    context: context,
    title: AppLocalizations.of(context).error,
    icon: Icons.error_outline_outlined,
    body: errorBody,
    isDismissible: isDismissible,
    buttons: [
      ButtonWidget(
        buttonType: ButtonType.primary,
        labelText: AppLocalizations.of(context).ok,
        buttonAction: ButtonAction.first,
        isInAlert: true,
      ),
      ButtonWidget(
        buttonType: ButtonType.secondary,
        labelText: AppLocalizations.of(context).contactSupport,
        buttonAction: ButtonAction.second,
        onTap: () async {
          await sendLogs(
            context,
            AppLocalizations.of(context).contactSupport,
            "support@ente.com",
            postShare: () {},
          );
        },
      ),
    ],
  );
  return result;
}

Future<void> showGenericErrorBottomSheet({
  required BuildContext context,
  required Object? error,
}) async {
  final errorBody = parseErrorForUI(
    context,
    AppLocalizations.of(
      context,
    ).itLooksLikeSomethingWentWrongPleaseRetryAfterSome,
    error: error,
  );
  await showAlertBottomSheet(
    context,
    title: AppLocalizations.of(context).error,
    message: errorBody,
    assetPath: 'assets/warning-grey.png',
    buttons: [
      ButtonWidgetV2(
        buttonType: ButtonTypeV2.secondary,
        labelText: AppLocalizations.of(context).contactSupport,
        onTap: () async {
          await sendLogs(
            context,
            AppLocalizations.of(context).contactSupport,
            "support@ente.com",
            postShare: () {},
          );
        },
      ),
    ],
  );
}

/// Legacy two-choice dialog helper backed by [showDialogWidget].
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

/// Compatibility adapter for legacy Photos choice sheets.
///
/// Preserves existing two-choice [ButtonResult] behavior while rendering
/// through [BottomSheetComponent]. Prefer [BottomSheetComponent] directly for
/// new sheets.
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

/// Compatibility adapter for legacy Photos text-input dialogs.
///
/// Returns null on successful submit, [ButtonResult] on cancel, and [Exception]
/// on submit failure. Prefer [BottomSheetComponent] directly for new sheets.
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

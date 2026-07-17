import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:email_validator/email_validator.dart';
import "package:file_saver/file_saver.dart";
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import "package:intl/intl.dart";
import 'package:logging/logging.dart';
import 'package:open_mail_app/open_mail_app.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/error-reporting/super_logging.dart';
import "package:photos/generated/l10n.dart";
import 'package:photos/theme/ente_theme.dart';
import "package:photos/ui/common/progress_dialog.dart";
import 'package:photos/ui/components/base_bottom_sheet.dart';
import 'package:photos/ui/components/buttons/button_widget.dart';
import 'package:photos/ui/components/buttons/button_widget_v2.dart';
import 'package:photos/ui/components/dialog_widget.dart';
import 'package:photos/ui/components/models/button_type.dart';
import 'package:photos/ui/notification/toast.dart';
import 'package:photos/ui/tools/debug/log_file_viewer.dart';
import 'package:photos/utils/dialog_util.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

final Logger _logger = Logger('email_util');

bool isValidEmail(String? email) {
  if (email == null) {
    return false;
  }
  return EmailValidator.validate(email);
}

Future<void> sendLogs(
  BuildContext context,
  String title,
  String toEmail, {
  Function? postShare,
  String? subject,
  String? body,
}) async {
  // ignore: unawaited_futures
  showDialogWidget(
    context: context,
    title: AppLocalizations.of(context).reportABug,
    icon: Icons.bug_report_outlined,
    body: AppLocalizations.of(context).logsDialogBody,
    buttons: [
      ButtonWidget(
        isInAlert: true,
        buttonType: ButtonType.neutral,
        labelText: AppLocalizations.of(context).reportABug,
        buttonAction: ButtonAction.first,
        shouldSurfaceExecutionStates: false,
        onTap: () async {
          await _sendLogs(context, toEmail, subject, body);
          if (postShare != null) {
            postShare();
          }
        },
      ),
      //isInAlert is false here as we don't want to the dialog to dismiss
      //on pressing this button
      ButtonWidget(
        buttonType: ButtonType.secondary,
        labelText: AppLocalizations.of(context).viewLogs,
        buttonAction: ButtonAction.second,
        onTap: () async {
          // ignore: unawaited_futures
          showDialog(
            useRootNavigator: false,
            context: context,
            builder: (BuildContext context) {
              return LogFileViewer(SuperLogging.logFile!);
            },
            barrierColor: Colors.black87,
            barrierDismissible: false,
          );
        },
      ),
      ButtonWidget(
        buttonType: ButtonType.secondary,
        labelText: AppLocalizations.of(context).exportLogs,
        buttonAction: ButtonAction.third,
        shouldSurfaceExecutionStates: false,
        onTap: () async {
          final zipFilePath = await getZippedLogsFile(context);
          if (!context.mounted) return;
          await exportLogs(context, zipFilePath);
        },
      ),
      ButtonWidget(
        isInAlert: true,
        buttonType: ButtonType.secondary,
        labelText: AppLocalizations.of(context).cancel,
        buttonAction: ButtonAction.cancel,
      ),
    ],
  );
}

Future<void> _sendLogs(
  BuildContext context,
  String toEmail,
  String? subject,
  String? body,
) async {
  final String zipFilePath = await getZippedLogsFile(context);
  if (!context.mounted) return;
  final didOpenComposer = await sendLogsWithSubjectAndBody(
    context,
    toEmail: toEmail,
    subject: subject,
    body: body,
    zipFilePath: zipFilePath,
  );
  if (!didOpenComposer) {
    if (!context.mounted) return;
    Navigator.of(context).pop();
    if (!context.mounted) return;
    await shareLogs(context, toEmail, zipFilePath);
  }
}

Future<bool> sendLogsWithSubjectAndBody(
  BuildContext context, {
  required String toEmail,
  String? subject,
  String? body,
  String? zipFilePath,
}) async {
  final effectiveZipFilePath = zipFilePath ?? await getZippedLogsFile(context);
  if (!context.mounted) return false;
  return sendComposedEmail(
    context,
    to: toEmail,
    subject: subject ?? '',
    body: body ?? '',
    attachmentPaths: [effectiveZipFilePath],
  );
}

Future<void> triggerSendLogs(
  String toEmail,
  String? subject,
  String? body,
) async {
  final String zipFilePath = await getZippedLogsFile(null);
  final Email email = Email(
    recipients: [toEmail],
    subject: subject ?? '',
    body: body ?? '',
    attachmentPaths: [zipFilePath],
    isHTML: false,
  );
  try {
    await FlutterEmailSender.send(email);
  } catch (e, s) {
    _logger.severe('email sender failed', e, s);
  }
}

Future<String> getZippedLogsFile(BuildContext? context) async {
  late final ProgressDialog dialog;
  if (context != null) {
    dialog = createProgressDialog(
      context,
      AppLocalizations.of(context).preparingLogs,
    );
    await dialog.show();
  }
  final logsPath = (await getApplicationSupportDirectory()).path;
  final logsDirectory = Directory(logsPath + "/logs");
  final tempPath = (await getTemporaryDirectory()).path;
  final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
    ':',
    '-',
  );
  final zipFilePath = tempPath + "/logs-$timestamp.zip";
  final encoder = ZipFileEncoder();
  encoder.create(zipFilePath);
  await encoder.addDirectory(logsDirectory);
  await encoder.close();
  if (context != null) {
    await dialog.hide();
  }
  return zipFilePath;
}

Future<void> shareLogs(
  BuildContext context,
  String toEmail,
  String zipFilePath,
) async {
  final result = await showDialogWidget(
    context: context,
    title: AppLocalizations.of(context).emailYourLogs,
    body: AppLocalizations.of(context).pleaseSendTheLogsTo(toEmail: toEmail),
    buttons: [
      ButtonWidget(
        buttonType: ButtonType.neutral,
        labelText: AppLocalizations.of(context).copyEmailAddress,
        isInAlert: true,
        buttonAction: ButtonAction.first,
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: toEmail));
        },
        shouldShowSuccessConfirmation: true,
      ),
      ButtonWidget(
        buttonType: ButtonType.neutral,
        labelText: AppLocalizations.of(context).exportLogs,
        isInAlert: true,
        buttonAction: ButtonAction.second,
      ),
      ButtonWidget(
        buttonType: ButtonType.secondary,
        labelText: AppLocalizations.of(context).cancel,
        isInAlert: true,
        buttonAction: ButtonAction.cancel,
      ),
    ],
  );
  if (result?.action != null && result!.action == ButtonAction.second) {
    if (!context.mounted) return;
    await exportLogs(context, zipFilePath);
  }
}

Future<void> exportLogs(BuildContext context, String zipFilePath) async {
  final Size size = MediaQuery.of(context).size;
  if (Platform.isAndroid) {
    final DateTime now = DateTime.now().toUtc();
    final String shortMonthName = DateFormat('MMM').format(now); // Short month
    final String logFileName =
        'ente-logs-${now.year}-$shortMonthName-${now.day}-${now.hour}-${now.minute}';
    await FileSaver.instance.saveAs(
      name: logFileName,
      filePath: zipFilePath,
      mimeType: MimeType.zip,
      fileExtension: 'zip',
    );
  } else {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(zipFilePath, mimeType: 'application/zip')],
        sharePositionOrigin: Rect.fromLTWH(0, 0, size.width, size.height / 2),
      ),
    );
  }
}

Future<void> sendEmail(
  BuildContext context, {
  required String to,
  String? subject,
  String? body,
}) async {
  try {
    final String clientDebugInfo = await _clientInfo();
    if (!context.mounted) return;
    final didOpenComposer = await sendComposedEmail(
      context,
      to: to,
      subject: subject ?? '[Support]',
      body: (body ?? '') + clientDebugInfo,
    );
    if (!didOpenComposer) {
      if (!context.mounted) return;
      await _showNoMailAppsSheet(context, to);
    }
  } catch (e) {
    _logger.severe("Failed to send emailContent to $to", e);
    if (!context.mounted) return;
    await _showNoMailAppsSheet(context, to);
  }
}

Future<void> openEmailComposer(
  BuildContext context, {
  required String to,
}) async {
  try {
    final didOpenComposer = await sendComposedEmail(
      context,
      to: to,
      subject: '',
      body: '',
    );
    if (!didOpenComposer) {
      if (!context.mounted) return;
      await _showNoMailAppsSheet(context, to);
    }
  } catch (e, s) {
    _logger.severe("Failed to open email composer to $to", e, s);
    if (!context.mounted) return;
    await _showNoMailAppsSheet(context, to);
  }
}

Future<bool> sendComposedEmail(
  BuildContext context, {
  required String to,
  required String subject,
  required String body,
  List<String>? attachmentPaths,
}) async {
  try {
    final hasAttachment = attachmentPaths != null && attachmentPaths.isNotEmpty;
    if (hasAttachment) {
      final email = Email(
        recipients: [to],
        subject: subject,
        body: body,
        attachmentPaths: attachmentPaths,
        isHTML: false,
      );
      await FlutterEmailSender.send(email);
      return true;
    }

    final emailContent = EmailContent(to: [to], subject: subject, body: body);

    if (Platform.isAndroid) {
      // Special handling due to issue in proton mail android client
      // https://github.com/ente/photos-app/pull/253
      final params = _buildMailtoUri(to, subject: subject, body: body);
      if (!await canLaunchUrl(params)) {
        return false;
      }
      await launchUrl(params);
      return true;
    }

    final result = await OpenMailApp.composeNewEmailInMailApp(
      nativePickerTitle: AppLocalizations.of(context).selectMailApp,
      emailContent: emailContent,
    );
    if (!result.didOpen && !result.canOpen) {
      return false;
    }
    if (!result.didOpen && result.canOpen) {
      if (!context.mounted) return false;
      await showCupertinoModalPopup(
        context: context,
        builder: (sheetContext) => CupertinoActionSheet(
          title: Text(
            AppLocalizations.of(sheetContext).selectMailApp + " \n $to",
          ),
          actions: [
            for (final app in result.options)
              CupertinoActionSheetAction(
                child: Text(app.name),
                onPressed: () async {
                  await OpenMailApp.composeNewEmailInSpecificMailApp(
                    mailApp: app,
                    emailContent: emailContent,
                  );
                  if (sheetContext.mounted) {
                    Navigator.of(sheetContext).pop();
                  }
                },
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            child: Text(AppLocalizations.of(sheetContext).cancel),
            onPressed: () {
              Navigator.of(sheetContext).pop();
            },
          ),
        ),
      );
    }
    return true;
  } catch (e, s) {
    _logger.severe("Failed to send composed email to $to", e, s);
    return false;
  }
}

Uri _buildMailtoUri(String to, {String? subject, String? body}) {
  final queryParameters = <String, String>{};
  if (subject != null && subject.isNotEmpty) {
    queryParameters["subject"] = subject;
  }
  if (body != null && body.isNotEmpty) {
    queryParameters["body"] = body;
  }
  return Uri(
    scheme: "mailto",
    path: to,
    queryParameters: queryParameters.isEmpty ? null : queryParameters,
  );
}

Future<String> getSupportDeviceInfo() async {
  final packageInfo = await PackageInfo.fromPlatform();
  final platformDeviceInfo = await _getPlatformDeviceInfo();
  final buffer = StringBuffer()
    ..writeln(
      "App version: ${packageInfo.version} (${packageInfo.buildNumber})",
    )
    ..writeln("OS version: ${platformDeviceInfo.osVersion}")
    ..write("Device model: ${platformDeviceInfo.deviceModel}");
  return buffer.toString();
}

String buildSupportEmailBody({required String message, String? deviceInfo}) {
  final trimmedMessage = message.trim();
  final trimmedDeviceInfo = deviceInfo?.trim();
  if (trimmedDeviceInfo == null || trimmedDeviceInfo.isEmpty) {
    return trimmedMessage;
  }
  if (trimmedMessage.isEmpty) {
    return trimmedDeviceInfo;
  }
  return "$trimmedMessage\n\n-------------------\n$trimmedDeviceInfo";
}

Future<String> _clientInfo() async {
  final packageInfo = await PackageInfo.fromPlatform();
  final supportDeviceInfo = await getSupportDeviceInfo();
  final String debugInfo =
      '\n\n\n\n ------------------- \nFollowing information can '
      'help us in debugging if you are facing any issue '
      '\nRegistered email: ${Configuration.instance.getEmail()}'
      '\nClient: ${packageInfo.packageName}'
      '\n$supportDeviceInfo';
  return debugInfo;
}

Future<void> _showNoMailAppsSheet(BuildContext context, String toEmail) async {
  if (!context.mounted) {
    return;
  }
  await showBaseBottomSheet<void>(
    context,
    title: AppLocalizations.of(context).noEmailAppFound,
    headerSpacing: 16,
    child: _NoMailAppsSheet(toEmail: toEmail),
  );
}

class _NoMailAppsSheet extends StatelessWidget {
  final String toEmail;

  const _NoMailAppsSheet({required this.toEmail});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = getEnteTextTheme(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.pleaseEmailUsAt(toEmail: toEmail),
          style: textTheme.smallMuted,
        ),
        const SizedBox(height: 16),
        ButtonWidgetV2(
          buttonType: ButtonTypeV2.primary,
          labelText: l10n.copyEmailAddress,
          onTap: () async {
            await _copyEmailAddress(context, toEmail);
          },
        ),
      ],
    );
  }
}

Future<void> _copyEmailAddress(BuildContext context, String toEmail) async {
  await Clipboard.setData(ClipboardData(text: toEmail));
  if (context.mounted) {
    showShortToast(context, AppLocalizations.of(context).copied);
  }
}

Future<({String osVersion, String deviceModel})>
_getPlatformDeviceInfo() async {
  try {
    final deviceInfoPlugin = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfoPlugin.androidInfo;
      final deviceModel = "${androidInfo.manufacturer} ${androidInfo.model}"
          .trim();
      final osVersion = "Android ${androidInfo.version.release}";
      return (
        osVersion: osVersion,
        deviceModel: deviceModel.isEmpty ? "Android device" : deviceModel,
      );
    }
    if (Platform.isIOS) {
      final iosInfo = await deviceInfoPlugin.iosInfo;
      final machine = iosInfo.utsname.machine.trim();
      return (
        osVersion: "iOS ${iosInfo.systemVersion}",
        deviceModel: machine.isEmpty ? iosInfo.model : machine,
      );
    }
  } catch (e, s) {
    _logger.severe("Failed to fetch platform device info", e, s);
  }
  return (osVersion: Platform.operatingSystem, deviceModel: "Unknown device");
}

import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:email_validator/email_validator.dart';
import 'package:ente_mail/ente_mail.dart';
import "package:ente_strings/ente_strings.dart";
import 'package:ente_ui/pages/log_file_viewer.dart';
import "package:file_saver/file_saver.dart";
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import "package:intl/intl.dart";
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/error-reporting/super_logging.dart';
import 'package:photos/theme/ente_theme.dart';
import "package:photos/ui/common/progress_dialog.dart";
import 'package:photos/ui/components/base_bottom_sheet.dart';
import 'package:photos/ui/components/buttons/button_widget.dart';
import 'package:photos/ui/components/buttons/button_widget_v2.dart';
import 'package:photos/ui/components/dialog_widget.dart';
import 'package:photos/ui/components/models/button_type.dart';
import 'package:photos/ui/notification/toast.dart';
import 'package:photos/utils/dialog_util.dart';
import 'package:share_plus/share_plus.dart';

final Logger _logger = Logger('email_util');
const MailComposer _mailComposer = MailComposer();

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
    title: context.strings.reportABug,
    icon: Icons.bug_report_outlined,
    body: context.strings.logsDialogBody,
    buttons: [
      ButtonWidget(
        isInAlert: true,
        buttonType: ButtonType.neutral,
        labelText: context.strings.reportABug,
        buttonAction: ButtonAction.first,
        shouldSurfaceExecutionStates: false,
        onTap: () async {
          await _sendLogs(context, toEmail, subject, body);
          if (postShare != null) {
            postShare();
          }
        },
      ),
      ButtonWidget(
        buttonType: ButtonType.secondary,
        labelText: context.strings.viewLogs,
        buttonAction: ButtonAction.second,
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => LogFileViewer(SuperLogging.logFile!),
            ),
          );
        },
      ),
      ButtonWidget(
        buttonType: ButtonType.secondary,
        labelText: context.strings.exportLogs,
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
        labelText: context.strings.cancel,
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
  final String zipFilePath = await getZippedLogsFile(
    context,
    reportText: buildSupportReportText(
      to: toEmail,
      subject: subject ?? '',
      body: body ?? '',
    ),
  );
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
  final effectiveZipFilePath =
      zipFilePath ??
      await getZippedLogsFile(
        context,
        reportText: buildSupportReportText(
          to: toEmail,
          subject: subject ?? '',
          body: body ?? '',
        ),
      );
  if (!context.mounted) return false;
  return sendComposedEmail(
    to: toEmail,
    subject: subject ?? '',
    body: body ?? '',
    attachmentPath: effectiveZipFilePath,
  );
}

Future<void> triggerSendLogs(
  String toEmail,
  String? subject,
  String? body,
) async {
  final String zipFilePath = await getZippedLogsFile(
    null,
    reportText: buildSupportReportText(
      to: toEmail,
      subject: subject ?? '',
      body: body ?? '',
    ),
  );
  final launched = await sendComposedEmail(
    to: toEmail,
    subject: subject ?? '',
    body: body ?? '',
    attachmentPath: zipFilePath,
  );
  if (!launched) {
    _logger.warning('Mail composer is unavailable');
  }
}

Future<String> getZippedLogsFile(
  BuildContext? context, {
  String? reportText,
}) async {
  late final ProgressDialog dialog;
  if (context != null) {
    dialog = createProgressDialog(context, context.strings.preparingLogs);
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
  if (reportText != null) {
    encoder.addArchiveFile(
      ArchiveFile.string('support-report.txt', reportText),
    );
  }
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
    title: context.strings.emailYourLogs,
    body: context.strings.pleaseSendTheLogsTo(toEmail: toEmail),
    buttons: [
      ButtonWidget(
        buttonType: ButtonType.neutral,
        labelText: context.strings.copyEmailAddress,
        isInAlert: true,
        buttonAction: ButtonAction.first,
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: toEmail));
        },
        shouldShowSuccessConfirmation: true,
      ),
      ButtonWidget(
        buttonType: ButtonType.neutral,
        labelText: context.strings.exportLogs,
        isInAlert: true,
        buttonAction: ButtonAction.second,
      ),
      ButtonWidget(
        buttonType: ButtonType.secondary,
        labelText: context.strings.cancel,
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
    final String shortMonthName = DateFormat('MMM').format(now);
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

Future<bool> sendComposedEmail({
  required String to,
  required String subject,
  required String body,
  String? attachmentPath,
}) async {
  try {
    final result = await _mailComposer.compose(
      MailDraft(
        recipient: to,
        subject: subject,
        body: body,
        attachment: attachmentPath == null
            ? null
            : MailAttachment(path: attachmentPath, mimeType: 'application/zip'),
      ),
    );
    if (result is MailUnavailable) {
      _logger.warning('Mail composer unavailable: ${result.reason.name}');
      return false;
    }
    return true;
  } catch (e, s) {
    _logger.severe("Failed to send composed email to $to", e, s);
    return false;
  }
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

String buildSupportReportText({
  required String to,
  required String subject,
  required String body,
}) => "To: $to\nSubject: $subject\n\n$body";

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
    title: context.strings.noEmailAppFound,
    headerSpacing: 16,
    child: _NoMailAppsSheet(toEmail: toEmail),
  );
}

class _NoMailAppsSheet extends StatelessWidget {
  final String toEmail;

  const _NoMailAppsSheet({required this.toEmail});

  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;
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
    showShortToast(context, context.strings.copied);
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

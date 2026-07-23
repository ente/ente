import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:ente_configuration/base_configuration.dart';
import 'package:ente_logging/logging.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart' as pure_utils;
import 'package:ente_strings/extensions.dart';
import 'package:ente_ui/components/base_bottom_sheet.dart';
import 'package:ente_ui/components/buttons/button_widget.dart';
import 'package:ente_ui/components/buttons/gradient_button.dart';
import 'package:ente_ui/components/buttons/models/button_type.dart';
import 'package:ente_ui/components/dialog_widget.dart';
import 'package:ente_ui/pages/log_file_viewer.dart';
import 'package:ente_ui/theme/ente_theme.dart';
import 'package:ente_ui/utils/toast_util.dart';
import 'package:ente_utils/file_saver_util.dart';
import 'package:ente_utils/share_utils.dart';
import "package:file_saver/file_saver.dart";
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import "package:intl/intl.dart";
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

final Logger _logger = Logger('email_util');

bool isValidEmail(String? email) {
  if (email == null) {
    return false;
  }
  return pure_utils.isValidEmail(email);
}

Future<void> sendLogs(
  BuildContext context,
  String toEmail, {
  Function? postShare,
  String? subject,
  String? body,
  String? dialogBody,
}) async {
  // ignore: unawaited_futures
  showDialogWidget(
    context: context,
    title: context.strings.reportABug,
    icon: Icons.bug_report_outlined,
    body: dialogBody ?? context.strings.logsDialogBody,
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
      //isInAlert is false here as we don't want to the dialog to dismiss
      //on pressing this button
      ButtonWidget(
        buttonType: ButtonType.secondary,
        labelText: context.strings.viewLogs,
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
        labelText: context.strings.exportLogs,
        buttonAction: ButtonAction.third,
        onTap: () async {
          final zipFilePath = await getZippedLogsFile();
          await exportLogs(null, zipFilePath);
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
  final String zipFilePath = await getZippedLogsFile();
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
    if (!context.mounted) {
      return;
    }
    Navigator.of(context).pop();
    await shareLogs(context, toEmail, zipFilePath);
  }
}

Future<void> shareLogs(
  BuildContext context,
  String toEmail,
  String zipFilePath,
) async {
  final result = await showDialogWidget(
    context: context,
    title: context.strings.emailYourLogs,
    body: context.strings.pleaseSendTheLogsTo(toEmail),
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
    await exportLogs(null, zipFilePath);
  }
}

Future<void> openSupportPage(String? subject, String? body) async {
  const url = "https://github.com/ente/ente/discussions/new?category=q-a";
  if (subject != null && body != null) {
    await launchUrl(Uri.parse("$url&title=$subject&body=$body"));
  } else {
    await launchUrl(Uri.parse(url));
  }
}

Future<String> getZippedLogsFile({String logsSubPath = "logs"}) async {
  final logsPath = (await getApplicationSupportDirectory()).path;
  final logsDirectory = Directory("$logsPath/$logsSubPath");
  final tempPath = (await pure_utils.DirectoryUtils.getTempsDir()).path;
  final zipFilePath = "$tempPath/logs.zip";
  final encoder = ZipFileEncoder();
  encoder.create(zipFilePath);
  await encoder.addDirectory(logsDirectory);
  await encoder.close();
  return zipFilePath;
}

Future<void> exportLogs(
  BuildContext? context,
  String zipFilePath, [
  bool isSharing = false,
]) async {
  if (!isSharing) {
    final DateTime now = DateTime.now().toUtc();
    final String shortMonthName = DateFormat('MMM').format(now); // Short month
    final String logFileName =
        'ente-logs-${now.year}-$shortMonthName-${now.day}-${now.hour}-${now.minute}';

    final bytes = await File(zipFilePath).readAsBytes();
    await FileSaverUtil.saveFile(logFileName, 'zip', bytes, MimeType.zip);
  } else {
    await shareFiles([
      XFile(zipFilePath, mimeType: 'application/zip'),
    ], context: context);
  }
}

Future<void> sendLogsViaEmail(
  String toEmail,
  String? subject,
  String? body,
) async {
  final String zipFilePath = await getZippedLogsFile();
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
    rethrow;
  }
}

Future<void> sendEmail(
  BuildContext context, {
  required String to,
  String? subject,
  String? body,
  BaseConfiguration? configuration,
}) async {
  try {
    final String clientDebugInfo = await _clientInfo(configuration);
    final String subject0 = subject ?? '[Support]';
    final String body0 = (body ?? '') + clientDebugInfo;

    if (Platform.isAndroid) {
      // Special handling due to issue in proton mail android client
      // https://github.com/ente/photos-app/pull/253
      final Uri params = Uri(
        scheme: 'mailto',
        path: to,
        query: 'subject=$subject0&body=$body0',
      );
      if (await canLaunchUrl(params)) {
        await launchUrl(params);
      } else {
        // this will trigger _showNoMailAppsDialog
        throw Exception('Could not launch ${params.toString()}');
      }
    } else {
      if (!context.mounted) {
        return;
      }
      _showNoMailAppsDialog(context, to);
    }
  } catch (e) {
    _logger.severe("Failed to send email to $to", e);
    if (context.mounted) {
      _showNoMailAppsDialog(context, to);
    }
  }
}

Future<String> _clientInfo(BaseConfiguration? configuration) async {
  final packageInfo = await PackageInfo.fromPlatform();
  final String debugInfo =
      '\n\n\n\n ------------------- \nFollowing information can '
      'help us in debugging if you are facing any issue '
      '\nRegistered email: ${configuration?.getEmail() ?? 'N/A'}'
      '\nClient: ${packageInfo.packageName}'
      '\nVersion : ${packageInfo.version}';
  return debugInfo;
}

void _showNoMailAppsDialog(BuildContext context, String toEmail) {
  showBaseBottomSheet(
    context,
    title: 'Contact Support',
    headerSpacing: 20,
    child: Builder(
      builder: (bottomSheetContext) {
        final colorScheme = getEnteColorScheme(bottomSheetContext);
        final textTheme = getEnteTextTheme(bottomSheetContext);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Email us at $toEmail',
              style: textTheme.body.copyWith(color: colorScheme.textMuted),
              textAlign: TextAlign.left,
            ),
            const SizedBox(height: 20),
            GradientButton(
              text: 'Copy Email Address',
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: toEmail));
                if (bottomSheetContext.mounted) {
                  Navigator.of(bottomSheetContext).pop();
                }
                if (context.mounted) {
                  showShortToast(context, 'Email address copied');
                }
              },
            ),
          ],
        );
      },
    ),
  );
}

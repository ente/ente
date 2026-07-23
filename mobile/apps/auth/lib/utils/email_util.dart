import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:email_validator/email_validator.dart';
import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/ui/components/buttons/button_widget.dart';
import 'package:ente_auth/ui/components/dialog_widget.dart';
import 'package:ente_auth/ui/components/models/button_type.dart';
import 'package:ente_auth/ui/tools/debug/log_file_viewer.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_auth/utils/directory_utils.dart' as auth_dir;
import 'package:ente_auth/utils/share_utils.dart' as auth_share;
import 'package:ente_auth/utils/toast_util.dart';
import 'package:ente_logging/logging.dart';
import 'package:ente_utils/ente_utils.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
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
  String title, {
  Function? postShare,
  String? subject,
  String? body,
}) async {
  final l10n = context.l10n;
  await showDialogWidget(
    context: context,
    title: title,
    icon: Icons.bug_report_outlined,
    body: l10n.sendLogsDescription,
    buttons: [
      ButtonWidget(
        isInAlert: true,
        buttonType: ButtonType.neutral,
        labelText: l10n.reportABug,
        buttonAction: ButtonAction.first,
        shouldSurfaceExecutionStates: false,
        onTap: () async {
          await openSupportPage(subject, body);
          if (postShare != null) {
            postShare();
          }
        },
      ),
      //isInAlert is false here as we don't want to the dialog to dismiss
      //on pressing this button
      ButtonWidget(
        buttonType: ButtonType.secondary,
        labelText: l10n.viewLogsAction,
        buttonAction: ButtonAction.second,
        onTap: () async {
          await showDialog(
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
        isInAlert: true,
        buttonType: ButtonType.secondary,
        labelText: l10n.exportLogs,
        buttonAction: ButtonAction.third,
        onTap: () async {
          Future.delayed(const Duration(milliseconds: 200), () {
            if (!context.mounted) return;
            auth_share.shareDialog(
              context,
              title,
              saveAction: () async {
                final zipFilePath = await getZippedLogsFile(context);
                if (!context.mounted) return;
                await exportLogs(context, zipFilePath);
              },
              sendAction: () async {
                final zipFilePath = await getZippedLogsFile(context);
                if (!context.mounted) return;
                await exportLogs(context, zipFilePath, true);
              },
            );
          });
        },
      ),
      ButtonWidget(
        isInAlert: true,
        buttonType: ButtonType.secondary,
        labelText: l10n.cancel,
        buttonAction: ButtonAction.cancel,
      ),
    ],
  );
}

Future<void> openSupportPage(String? subject, String? body) async {
  final baseSupportUri = Uri.https("github.com", "/ente/ente/discussions/new", {
    "category": "q-a",
  });
  final queryParameters = Map<String, String>.from(
    baseSupportUri.queryParameters,
  );
  if (subject != null && body != null) {
    queryParameters["title"] = subject;
    queryParameters["body"] = body;
  }
  final supportUri = baseSupportUri.replace(queryParameters: queryParameters);

  final launched = await launchUrl(supportUri);
  if (!launched) {
    _logger.warning("Failed to open support discussions at $supportUri");
  }
  // final String zipFilePath = await getZippedLogsFile(context);
  // final Email email = Email(
  //   recipients: [toEmail],
  //   subject: subject ?? '',
  //   body: body ?? '',
  //   attachmentPaths: [zipFilePath],
  //   isHTML: false,
  // );
  // try {
  //   await FlutterEmailSender.send(email);
  // } catch (e, s) {
  //   _logger.severe('email sender failed', e, s);
  //   Navigator.of(context, rootNavigator: true).pop();
  //   await shareLogs(context, toEmail, zipFilePath);
  // }
}

Future<String> getZippedLogsFile(BuildContext context) async {
  final l10n = context.l10n;
  final dialog = createProgressDialog(context, l10n.preparingLogsTitle);
  await dialog.show();
  final logsPath = (await getApplicationSupportDirectory()).path;
  final logsDirectory = Directory("$logsPath/logs");
  final tempPath = (await auth_dir.DirectoryUtils.getTempsDir()).path;
  final zipFilePath =
      "$tempPath/logs-${Configuration.instance.getUserID() ?? 0}.zip";
  final encoder = ZipFileEncoder();
  encoder.create(zipFilePath);
  await encoder.addDirectory(logsDirectory);
  await encoder.close();
  await dialog.hide();
  return zipFilePath;
}

Future<void> shareLogs(
  BuildContext context,
  String toEmail,
  String zipFilePath,
) async {
  final l10n = context.l10n;
  final result = await showDialogWidget(
    context: context,
    title: l10n.emailYourLogs,
    body: l10n.pleaseSendTheLogsTo(toEmail),
    buttons: [
      ButtonWidget(
        buttonType: ButtonType.neutral,
        labelText: l10n.copyEmailAddress,
        isInAlert: true,
        buttonAction: ButtonAction.first,
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: toEmail));
        },
        shouldShowSuccessConfirmation: true,
      ),
      ButtonWidget(
        buttonType: ButtonType.neutral,
        labelText: l10n.exportLogs,
        isInAlert: true,
        buttonAction: ButtonAction.second,
      ),
      ButtonWidget(
        buttonType: ButtonType.secondary,
        labelText: l10n.cancel,
        isInAlert: true,
        buttonAction: ButtonAction.cancel,
      ),
    ],
  );
  if (result?.action != null && result!.action == ButtonAction.second) {
    if (!context.mounted) return;
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!context.mounted) return;
      auth_share.shareDialog(
        context,
        context.l10n.exportLogs,
        saveAction: () async {
          final zipFilePath = await getZippedLogsFile(context);
          if (!context.mounted) return;
          await exportLogs(context, zipFilePath);
        },
        sendAction: () async {
          final zipFilePath = await getZippedLogsFile(context);
          if (!context.mounted) return;
          await exportLogs(context, zipFilePath, true);
        },
      );
    });
  }
}

Future<void> exportLogs(
  BuildContext context,
  String zipFilePath, [
  bool isSharing = false,
]) async {
  final Size size = MediaQuery.of(context).size;
  if (!isSharing) {
    final DateTime now = DateTime.now().toUtc();
    final String shortMonthName = DateFormat('MMM').format(now); // Short month
    final String logFileName =
        'ente-logs-${now.year}-$shortMonthName-${now.day}-${now.hour}-${now.minute}';

    final bytes = await File(zipFilePath).readAsBytes();
    await FileSaverUtil.saveFile(logFileName, 'zip', bytes, MimeType.zip);
  } else {
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(zipFilePath, mimeType: 'application/zip')],
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
    if (!context.mounted) return;
    final String clientDebugInfo = await _clientInfo();
    final String subject0 = subject ?? '[Support]';
    final String body0 = (body ?? '') + clientDebugInfo;
    // final EmailContent email = EmailContent(
    //   to: [
    //     to,
    //   ],
    //   subject: subject ?? '[Support]',
    //   body: (body ?? '') + clientDebugInfo,
    // );
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
      if (!context.mounted) return;
      _showNoMailAppsDialog(context, to);
    }
  } catch (e) {
    _logger.severe("Failed to send email to $to", e);
    if (!context.mounted) return;
    _showNoMailAppsDialog(context, to);
  }
}

Future<String> _clientInfo() async {
  final packageInfo = await PackageInfo.fromPlatform();
  final String debugInfo =
      '\n\n\n\n ------------------- \nFollowing information can '
      'help us in debugging if you are facing any issue '
      '\nRegistered email: ${Configuration.instance.getEmail()}'
      '\nClient: ${packageInfo.packageName}'
      '\nVersion : ${packageInfo.version}';
  return debugInfo;
}

void _showNoMailAppsDialog(BuildContext context, String toEmail) {
  final l10n = context.l10n;
  showChoiceDialog(
    context,
    icon: Icons.email_outlined,
    title: l10n.emailUsMessage(toEmail),
    firstButtonLabel: l10n.copyEmailAddress,
    secondButtonLabel: l10n.ok,
    firstButtonOnTap: () async {
      await Clipboard.setData(ClipboardData(text: toEmail));
      if (!context.mounted) return;
      showShortToast(context, l10n.copied);
    },
  );
}

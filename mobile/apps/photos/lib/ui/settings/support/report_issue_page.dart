import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:photos/core/constants.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/settings/components/settings_page_scaffold.dart";
import "package:photos/ui/settings/support/no_mail_app_sheet.dart";
import "package:photos/utils/email_util.dart";

class ReportIssuePage extends StatefulWidget {
  const ReportIssuePage({super.key});

  @override
  State<ReportIssuePage> createState() => _ReportIssuePageState();
}

class _ReportIssuePageState extends State<ReportIssuePage> {
  static final _logger = Logger("ReportIssuePage");
  final _subjectController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _attachLogs = true;
  bool _isSending = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.componentColors;
    final subjectHasText = _subjectController.text.isNotEmpty;
    final descriptionHasText = _descriptionController.text.isNotEmpty;

    Widget copyIcon() => HugeIcon(
      icon: HugeIcons.strokeRoundedCopy01,
      size: IconSizes.small,
      color: colors.textLighter,
      strokeWidth: 1.6,
    );

    return SettingsPageScaffold(
      title: l10n.reportAnIssue,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: ButtonComponent(
            label: l10n.continueInMailApp,
            isDisabled: _isSending,
            shouldSurfaceExecutionStates: false,
            onTap: _onSend,
          ),
        ),
      ),
      children: [
        TextInputComponent(
          label: l10n.subject,
          hintText: l10n.oneLineAboutTheIssue,
          controller: _subjectController,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 1,
          onChanged: (_) => setState(() {}),
          suffix: subjectHasText ? copyIcon() : null,
          onSuffixTap: subjectHasText
              ? () => _copyToClipboard(_subjectController.text)
              : null,
        ),
        const SizedBox(height: 16),
        TextInputComponent(
          label: l10n.description,
          hintText: l10n.detailsAboutTheIssue,
          controller: _descriptionController,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 6,
          minLines: 6,
          onChanged: (_) => setState(() {}),
          suffix: descriptionHasText ? copyIcon() : null,
          onSuffixTap: descriptionHasText
              ? () => _copyToClipboard(_descriptionController.text)
              : null,
        ),
        const SizedBox(height: 16),
        MenuComponent(
          title: l10n.attachLogs,
          subtitle: l10n.attachLogsHelper,
          subtitleMaxLines: 2,
          trailing: ToggleSwitchComponent(
            selected: _attachLogs,
            onChanged: (_) {
              setState(() {
                _attachLogs = !_attachLogs;
              });
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      showShortToast(context, AppLocalizations.of(context).copied);
    }
  }

  Future<void> _onSend() async {
    if (_isSending) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final subject = _subjectController.text.trim();
    final description = _descriptionController.text.trim();
    if (subject.isEmpty) {
      showShortToast(context, l10n.pleaseEnterASubject);
      return;
    }
    if (description.isEmpty) {
      showShortToast(context, l10n.pleaseEnterADescription);
      return;
    }

    setState(() {
      _isSending = true;
    });

    const recipientEmail = supportEmail;
    String? logsZipFilePath;
    String? logsLabel;

    try {
      final deviceInfo = await getSupportDeviceInfo();
      final body = buildSupportEmailBody(
        message: description,
        deviceInfo: deviceInfo,
      );

      if (_attachLogs) {
        if (!mounted) return;
        logsZipFilePath = await getZippedLogsFile(context);
        logsLabel = l10n.export;
      }

      late final bool didOpenComposer;
      if (_attachLogs) {
        if (!mounted) return;
        didOpenComposer = await sendLogsWithSubjectAndBody(
          context,
          toEmail: recipientEmail,
          subject: subject,
          body: body,
          zipFilePath: logsZipFilePath,
        );
      } else {
        if (!mounted) return;
        didOpenComposer = await sendComposedEmail(
          context,
          to: recipientEmail,
          subject: subject,
          body: body,
        );
      }

      if (didOpenComposer && mounted) {
        Navigator.of(context).pop();
        return;
      }

      if (!didOpenComposer && mounted) {
        await showNoMailAppSheet(
          context,
          toEmail: recipientEmail,
          subject: subject,
          message: description,
          deviceInfo: deviceInfo,
          logsLabel: logsLabel,
          logsFilePath: logsZipFilePath,
        );
      }
    } catch (e, s) {
      _logger.severe("Failed to report issue", e, s);
      if (mounted) {
        showShortToast(context, l10n.somethingWentWrong);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }
}

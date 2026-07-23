import "package:ente_legacy/components/gradient_button.dart";
import "package:ente_legacy/components/recovery_date_selector.dart";
import "package:ente_legacy/models/emergency_models.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/base_bottom_sheet.dart";
import "package:ente_ui/theme/ente_theme.dart";
import "package:flutter/material.dart";

Future<TrustedContactResult?> showTrustedContactSheet(
  BuildContext context, {
  required EmergencyContact contact,
}) {
  final email = contact.emergencyContact.email;
  return showBaseBottomSheet<TrustedContactResult>(
    context,
    title: email,
    headerSpacing: 20,
    child: TrustedContactSheet(contact: contact),
  );
}

enum TrustedContactAction { revoke, updateTime }

class TrustedContactResult {
  final TrustedContactAction action;
  final int? selectedDays;

  TrustedContactResult({required this.action, this.selectedDays});
}

class TrustedContactSheet extends StatefulWidget {
  final EmergencyContact contact;

  const TrustedContactSheet({required this.contact, super.key});

  @override
  State<TrustedContactSheet> createState() => _TrustedContactSheetState();
}

class _TrustedContactSheetState extends State<TrustedContactSheet> {
  late int _selectedRecoveryDays;
  late int _originalRecoveryDays;

  @override
  void initState() {
    super.initState();
    _originalRecoveryDays = widget.contact.recoveryNoticeInDays;
    _selectedRecoveryDays = _originalRecoveryDays;
  }

  bool get _hasChanges => _selectedRecoveryDays != _originalRecoveryDays;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final isPending = widget.contact.isPendingInvite();
    final email = widget.contact.emergencyContact.email;

    final String description = isPending
        ? context.strings.trustedContactInvitePending(email)
        : context.strings.trustedContactAccepted(email);

    final String label = isPending
        ? context.strings.revokeInvite
        : context.strings.remove;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          description,
          style: textTheme.small.copyWith(color: colorScheme.textMuted),
        ),
        const SizedBox(height: 20),
        RecoveryDateSelector(
          selectedDays: _selectedRecoveryDays,
          onDaysChanged: (days) {
            setState(() {
              _selectedRecoveryDays = days;
            });
          },
        ),
        const SizedBox(height: 20),
        GradientButton(
          text: context.strings.updateTime,
          onTap: _hasChanges
              ? () {
                  Navigator.of(context).pop(
                    TrustedContactResult(
                      action: TrustedContactAction.updateTime,
                      selectedDays: _selectedRecoveryDays,
                    ),
                  );
                }
              : null,
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: () {
            Navigator.of(
              context,
            ).pop(TrustedContactResult(action: TrustedContactAction.revoke));
          },
          child: SizedBox(
            width: double.infinity,
            child: Center(
              child: Text(
                label,
                style: textTheme.bodyBold.copyWith(
                  color: colorScheme.warning400,
                  decoration: TextDecoration.underline,
                  decorationColor: colorScheme.warning400,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

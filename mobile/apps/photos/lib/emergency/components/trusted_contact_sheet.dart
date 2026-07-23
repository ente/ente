import "package:flutter/material.dart";
import "package:photos/emergency/components/recovery_date_selector.dart";
import "package:photos/emergency/model.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/base_bottom_sheet.dart";
import "package:photos/ui/components/buttons/button_widget_v2.dart";

Future<TrustedContactResult?> showTrustedContactSheet(
  BuildContext context, {
  required EmergencyContact contact,
}) {
  return showBaseBottomSheet<TrustedContactResult>(
    context,
    title: contact.emergencyContact.email,
    headerSpacing: 20,
    padding: const EdgeInsets.all(16),
    backgroundColor: getEnteColorScheme(context).backgroundColour,
    child: TrustedContactSheet(contact: contact),
  );
}

enum TrustedContactAction { revoke, updateTime }

class TrustedContactResult {
  final TrustedContactAction action;
  final int? selectedDays;

  const TrustedContactResult({required this.action, this.selectedDays});
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
    final l10n = AppLocalizations.of(context);

    final isPending = widget.contact.isPendingInvite();
    final email = widget.contact.emergencyContact.email;
    final description = isPending
        ? l10n.trustedContactInvitePending(email: email)
        : l10n.trustedContactAccepted(email: email);
    final removeLabel = isPending ? l10n.revokeInvite : l10n.remove;

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
        ButtonWidgetV2(
          buttonType: ButtonTypeV2.primary,
          labelText: l10n.updateTime,
          isDisabled: !_hasChanges,
          onTap: !_hasChanges
              ? null
              : () async {
                  Navigator.of(context).pop(
                    TrustedContactResult(
                      action: TrustedContactAction.updateTime,
                      selectedDays: _selectedRecoveryDays,
                    ),
                  );
                },
        ),
        const SizedBox(height: 16),
        Center(
          child: ButtonWidgetV2(
            buttonType: ButtonTypeV2.tertiaryCritical,
            labelText: removeLabel,
            onTap: () async {
              Navigator.of(context).pop(
                const TrustedContactResult(action: TrustedContactAction.revoke),
              );
            },
            shouldSurfaceExecutionStates: false,
          ),
        ),
      ],
    );
  }
}

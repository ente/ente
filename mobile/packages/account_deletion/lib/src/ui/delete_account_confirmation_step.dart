import 'package:ente_account_deletion/src/models/account_deletion_summary.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

class DeleteAccountConfirmationStep extends StatelessWidget {
  const DeleteAccountConfirmationStep({
    super.key,
    required this.summary,
    required this.summaryUnsupported,
    required this.isLoading,
    required this.confirmed,
    required this.onConfirmationChanged,
    required this.onRetrySummary,
  });

  final AccountDeletionSummary? summary;
  final bool summaryUnsupported;
  final bool isLoading;
  final bool confirmed;
  final ValueChanged<bool> onConfirmationChanged;
  final VoidCallback onRetrySummary;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final canConfirm = summary != null || summaryUnsupported;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.strings.permanentlyDeleteYourEnteAccount,
          style: TextStyles.display3.copyWith(color: colors.textBase),
        ),
        const SizedBox(height: Spacing.sm),
        Text(
          context.strings.oneAccountAcrossEnteApps,
          style: TextStyles.body.copyWith(color: colors.textLight),
        ),
        const SizedBox(height: Spacing.lg),
        _buildSummary(context),
        const SizedBox(height: Spacing.lg),
        InkWell(
          onTap: canConfirm ? () => onConfirmationChanged(!confirmed) : null,
          borderRadius: BorderRadius.circular(Radii.sm),
          child: LabeledControlComponent(
            control: CheckboxComponent(
              selected: confirmed,
              onChanged: canConfirm ? onConfirmationChanged : null,
              selectedColor: colors.warning,
            ),
            label: context.strings.confirmDeleteAccountAcrossApps,
          ),
        ),
      ],
    );
  }

  Widget _buildSummary(BuildContext context) {
    final colors = context.componentColors;
    final summary = this.summary;

    if (isLoading) {
      return const SizedBox(
        height: 196,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (summaryUnsupported) {
      return const _SummaryRows();
    }
    if (summary == null) {
      return MenuComponent(
        title: context.strings.somethingWentWrong,
        subtitle: context.strings.tryAgain,
        titleColor: colors.warning,
        leading: HugeIcon(
          icon: HugeIcons.strokeRoundedAlertCircle,
          color: colors.warning,
          size: IconSizes.small,
        ),
        trailing: HugeIcon(
          icon: HugeIcons.strokeRoundedRefresh,
          color: colors.textLight,
          size: IconSizes.small,
        ),
        onTap: onRetrySummary,
      );
    }
    return _SummaryRows(summary: summary);
  }
}

class _SummaryRows extends StatelessWidget {
  const _SummaryRows({this.summary});

  final AccountDeletionSummary? summary;

  @override
  Widget build(BuildContext context) {
    final summary = this.summary;
    final numberFormat = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toLanguageTag(),
    );
    return Column(
      children: [
        _row(
          assetName: 'photos.png',
          title: summary == null
              ? context.strings.entePhotos
              : context.strings.photosAndVideosCount(
                  summary.photosAndVideosCount,
                  numberFormat.format(summary.photosAndVideosCount),
                ),
          subtitle: summary == null ? null : context.strings.entePhotos,
        ),
        const SizedBox(height: Spacing.sm),
        _row(
          assetName: 'auth.png',
          title: summary == null
              ? context.strings.enteAuth
              : context.strings.authenticatorCodesCount(
                  summary.authenticatorCodesCount,
                  numberFormat.format(summary.authenticatorCodesCount),
                ),
          subtitle: summary == null ? null : context.strings.enteAuth,
        ),
        const SizedBox(height: Spacing.sm),
        _row(
          assetName: 'locker.png',
          title: summary == null
              ? context.strings.enteLocker
              : context.strings.lockerRecordsCount(
                  summary.lockerRecordsCount,
                  numberFormat.format(summary.lockerRecordsCount),
                ),
          subtitle: summary == null ? null : context.strings.enteLocker,
        ),
      ],
    );
  }

  Widget _row({
    required String assetName,
    required String title,
    String? subtitle,
  }) {
    return MenuComponent(
      title: title,
      subtitle: subtitle,
      titleMaxLines: 1,
      subtitleMaxLines: 1,
      leading: SizedBox(
        width: 24,
        height: 24,
        child: Image.asset(
          'assets/$assetName',
          package: 'ente_account_deletion',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

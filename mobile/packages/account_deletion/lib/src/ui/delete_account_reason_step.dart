import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

enum DeleteAccountReason {
  missingFeature,
  unexpectedBehaviour,
  foundAnotherService,
  notListed,
}

extension DeleteAccountReasonExtension on DeleteAccountReason {
  String get apiValue {
    return switch (this) {
      DeleteAccountReason.missingFeature => 'missing_feature',
      DeleteAccountReason.unexpectedBehaviour => 'unexpected_behaviour',
      DeleteAccountReason.foundAnotherService => 'found_another_service',
      DeleteAccountReason.notListed => 'not_listed',
    };
  }

  String label(BuildContext context) {
    return switch (this) {
      DeleteAccountReason.missingFeature =>
        context.strings.deleteReasonMissingFeature,
      DeleteAccountReason.unexpectedBehaviour =>
        context.strings.deleteReasonBehaviour,
      DeleteAccountReason.foundAnotherService =>
        context.strings.deleteReasonFoundAnotherService,
      DeleteAccountReason.notListed => context.strings.deleteReasonNotListed,
    };
  }
}

class DeleteAccountReasonStep extends StatelessWidget {
  const DeleteAccountReasonStep({
    super.key,
    required this.selectedReason,
    required this.feedbackController,
    required this.onReasonChanged,
  });

  final DeleteAccountReason? selectedReason;
  final TextEditingController feedbackController;
  final ValueChanged<DeleteAccountReason> onReasonChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.strings.whyAreYouLeaving,
          style: TextStyles.display3.copyWith(color: colors.textBase),
        ),
        const SizedBox(height: Spacing.sm),
        Text(
          context.strings.thisHelpsUsImproveEnte,
          style: TextStyles.body.copyWith(color: colors.textLight),
        ),
        const SizedBox(height: Spacing.lg),
        _ReasonPicker(
          selectedReason: selectedReason,
          onReasonChanged: onReasonChanged,
        ),
        const SizedBox(height: Spacing.lg),
        TextInputComponent(
          controller: feedbackController,
          label: context.strings.anythingElse,
          hintText: context.strings.shareYourFeedbackHere,
          minLines: 5,
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          autocorrect: true,
        ),
      ],
    );
  }
}

class _ReasonPicker extends StatelessWidget {
  const _ReasonPicker({
    required this.selectedReason,
    required this.onReasonChanged,
  });

  final DeleteAccountReason? selectedReason;
  final ValueChanged<DeleteAccountReason> onReasonChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.strings.reasonForLeaving,
              style: TextStyles.bodyBold.copyWith(color: colors.textBase),
            ),
            const SizedBox(width: 2),
            Text(
              '*',
              style: TextStyles.bodyBold.copyWith(color: colors.warning),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            return EntePopupMenuButton<DeleteAccountReason>(
              menuWidth: constraints.maxWidth,
              optionsBuilder: () => DeleteAccountReason.values.map((reason) {
                return EntePopupMenuOption<DeleteAccountReason>(
                  value: reason,
                  label: reason.label(context),
                  isActive: reason == selectedReason,
                  activeTrailingWidget: HugeIcon(
                    icon: HugeIcons.strokeRoundedTick02,
                    color: colors.primary,
                    size: IconSizes.medium,
                  ),
                );
              }).toList(),
              onSelected: onReasonChanged,
              child: Padding(
                padding: const EdgeInsets.only(bottom: Spacing.sm),
                child: Container(
                  width: constraints.maxWidth,
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                  decoration: BoxDecoration(
                    color: colors.fillLight,
                    borderRadius: BorderRadius.circular(Radii.button),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          selectedReason?.label(context) ??
                              context.strings.selectReason,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyles.body.copyWith(
                            color: selectedReason == null
                                ? colors.textLighter
                                : colors.textBase,
                          ),
                        ),
                      ),
                      Icon(Icons.keyboard_arrow_down, color: colors.textLight),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

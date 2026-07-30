import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/ui/components/save_to_locker_banner.dart";
import "package:locker/ui/pages/save_page.dart";

const _optionSpacing = 10.0;
const _optionIconSize = 20.0;
const _optionPadding = EdgeInsets.symmetric(
  horizontal: Spacing.md,
  vertical: Spacing.xxl,
);

class SaveToLockerEmptyStateWidget extends StatelessWidget {
  const SaveToLockerEmptyStateWidget({
    super.key,
    required this.onUploadDocument,
  });

  final Future<bool> Function() onUploadDocument;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SaveToLockerBanner(),
        for (final option in saveOptions(context)) ...[
          const SizedBox(height: _optionSpacing),
          _SaveOptionTile(
            title: option.title,
            description: option.description,
            icon: option.icon,
            onTap: () => handleSaveOption(
              context,
              option.type,
              onUploadDocument: onUploadDocument,
            ),
          ),
        ],
      ],
    );
  }
}

class _SaveOptionTile extends StatelessWidget {
  const _SaveOptionTile({
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String description;
  final List<List<dynamic>> icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final borderRadius = BorderRadius.circular(Radii.button);
    return Material(
      color: colors.fillLight,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        child: Padding(
          padding: _optionPadding,
          child: Row(
            children: [
              SizedBox.square(
                dimension: 36,
                child: Center(
                  child: HugeIcon(
                    icon: icon,
                    color: colors.primary,
                    size: _optionIconSize,
                  ),
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyles.body.copyWith(color: colors.textBase),
                    ),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyles.mini.copyWith(color: colors.textLight),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.md),
              SizedBox.square(
                dimension: 36,
                child: Center(
                  child: Icon(Icons.chevron_right, color: colors.textBase),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

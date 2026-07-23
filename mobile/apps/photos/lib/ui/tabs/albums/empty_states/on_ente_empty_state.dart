import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/ui/common/backup_flow_helper.dart";
import "package:photos/ui/tabs/albums/empty_states/empty_state_feature_row.dart";

class OnEnteEmptyState extends StatelessWidget {
  const OnEnteEmptyState({super.key});

  static const _topPadding = 32.0;
  static const _sectionSpacing = 48.0;
  static const _contentWidth = 343.0;
  static const _featureWidth = 300.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final strings = AppLocalizations.of(context);
    final bottomPadding = 64 + MediaQuery.paddingOf(context).bottom + 32;
    final features = [
      strings.albumsOnEnteEmptyFeatureAccessAnyDevice,
      strings.albumsOnEnteEmptyFeatureShareLovedOnes,
      strings.albumsOnEnteEmptyFeaturePrivacy,
    ];

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, _topPadding, 16, bottomPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset("assets/on_ente.png"),
            const SizedBox(height: _sectionSpacing),
            SizedBox(
              width: _contentWidth,
              child: Column(
                children: [
                  Text(
                    strings.albumsOnEnteEmptyTitle,
                    textAlign: TextAlign.center,
                    style: TextStyles.display2.copyWith(color: colors.textBase),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: _featureWidth,
                    child: Column(
                      children: [
                        EmptyStateBulletFeatureRow(label: features[0]),
                        const SizedBox(height: 12),
                        EmptyStateBulletFeatureRow(label: features[1]),
                        const SizedBox(height: 12),
                        EmptyStateBulletFeatureRow(label: features[2]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: _sectionSpacing),
            ButtonComponent(
              label: strings.albumsOnEnteEmptyCta,
              shouldSurfaceExecutionStates: false,
              onTap: () async {
                await handleFolderSelectionBackupFlow(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

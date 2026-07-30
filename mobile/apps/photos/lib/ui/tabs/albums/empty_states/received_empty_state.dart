import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/ui/tabs/albums/empty_states/empty_state_feature_row.dart";

class ReceivedEmptyState extends StatelessWidget {
  const ReceivedEmptyState({super.key});

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
      strings.albumsReceivedEmptyFeatureSharedByOthers,
      strings.albumsReceivedEmptyFeatureAcceptInvites,
      strings.albumsReceivedEmptyFeatureSaveToLibrary,
    ];

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, _topPadding, 16, bottomPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: _contentWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset("assets/shared.png", fit: BoxFit.contain),
                  const SizedBox(height: _sectionSpacing),
                  Text(
                    strings.albumsReceivedEmptyTitle,
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
            const SizedBox(height: 120),
          ],
        ),
      ),
    );
  }
}

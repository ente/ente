import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/ui/account/email_entry_page.dart";
import "package:photos/ui/collections/collection_action_sheet.dart";
import "package:photos/ui/components/banners/banner_action_button.dart";
import "package:photos/ui/tabs/albums/empty_states/empty_state_feature_row.dart";

class FeedEmptyState extends StatelessWidget {
  const FeedEmptyState({required this.localGalleryMode, super.key});

  final bool localGalleryMode;

  static const _topPadding = 32.0;
  static const _sectionSpacing = 48.0;
  static const _contentWidth = 343.0;
  static const _featureWidth = 300.0;
  static const _assetHeight = 150.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final strings = AppLocalizations.of(context);
    final bottomPadding = 64 + MediaQuery.paddingOf(context).bottom + 32;
    final content = _content(context, strings);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  _topPadding,
                  16,
                  bottomPadding,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _FeedAssetSlot(assetPath: content.assetPath),
                    const SizedBox(height: _sectionSpacing),
                    SizedBox(
                      width: _contentWidth,
                      child: Column(
                        children: [
                          Text(
                            content.title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: "Nunito",
                              fontWeight: FontWeight.w800,
                              fontSize: 24,
                              height: 28 / 24,
                              letterSpacing: 0,
                              color: colors.textBase,
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: _featureWidth,
                            child: Column(
                              children: [
                                EmptyStateBulletFeatureRow(
                                  label: content.features[0],
                                ),
                                const SizedBox(height: 12),
                                EmptyStateBulletFeatureRow(
                                  label: content.features[1],
                                ),
                                const SizedBox(height: 12),
                                EmptyStateBulletFeatureRow(
                                  label: content.features[2],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: _sectionSpacing),
                    SizedBox(
                      width: content.showTag ? _featureWidth : _contentWidth,
                      child: BannerActionButton(
                        label: content.buttonLabel,
                        variant: BannerActionButtonVariant.primary,
                        showTag: content.showTag,
                        onTap: content.onTap,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  _FeedEmptyStateContent _content(
    BuildContext context,
    AppLocalizations strings,
  ) {
    if (localGalleryMode) {
      return _FeedEmptyStateContent(
        assetPath: "assets/shared.png",
        title: strings.albumsSharedEmptyTitle,
        features: [
          strings.albumsSharedEmptyFeatureShareLovedOnes,
          strings.albumsSharedEmptyFeatureReactAndComment,
          strings.albumsSharedEmptyFeaturePrivacy,
        ],
        buttonLabel: strings.getStarted,
        showTag: true,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const EmailEntryPage(
                showReferralSourceField: false,
                referralSource: "Offline",
              ),
            ),
          );
        },
      );
    }

    return _FeedEmptyStateContent(
      assetPath: "assets/feed.png",
      title: strings.albumsSharedEmptyTitle,
      features: [
        strings.albumsSharedEmptyFeatureShareLovedOnes,
        strings.albumsSharedEmptyFeatureReactAndComment,
        strings.albumsSharedEmptyFeaturePrivacy,
      ],
      buttonLabel: strings.shareAnAlbum,
      onTap: () {
        showCollectionActionSheet(
          context,
          actionType: CollectionActionType.shareCollection,
        );
      },
    );
  }
}

class _FeedEmptyStateContent {
  const _FeedEmptyStateContent({
    required this.assetPath,
    required this.title,
    required this.features,
    required this.buttonLabel,
    required this.onTap,
    this.showTag = false,
  });

  final String? assetPath;
  final String title;
  final List<String> features;
  final String buttonLabel;
  final VoidCallback onTap;
  final bool showTag;
}

class _FeedAssetSlot extends StatelessWidget {
  const _FeedAssetSlot({required this.assetPath});

  final String? assetPath;

  @override
  Widget build(BuildContext context) {
    final path = assetPath;
    if (path != null) {
      return Image.asset(path);
    }

    return const SizedBox(
      width: FeedEmptyState._contentWidth,
      height: FeedEmptyState._assetHeight,
    );
  }
}

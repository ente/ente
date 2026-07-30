import "dart:math" as math;

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/account/email_entry_page.dart";

class GetStartedBanner extends StatefulWidget {
  const GetStartedBanner({super.key});

  @override
  State<GetStartedBanner> createState() => _GetStartedBannerState();
}

class _GetStartedBannerState extends State<GetStartedBanner> {
  static const _bannerHeight = 116.0;
  static const _cardRadius = Radii.lg;
  static const _contentLeftPadding = 18.0;
  static const _contentTopPadding = 16.0;
  static const _contentBottomPadding = 12.0;
  static const _titleMaxWidth = 280.0;
  static const _bodyTextMaxWidth = 232.0;
  static const _duckWidth = 118.0;
  static const _duckTextReservedWidth = 102.0;
  static const _closeTextReservedWidth = 58.0;
  static const _duckRightInset = -4.0;
  static const _duckBottomInset = -2.0;
  static const _closeInset = 8.0;
  static const _ctaIconGap = 4.0;
  static const _maxTextScaleFactor = 1.3;
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    if (localSettings.isLocalGalleryGetStartedBannerDismissed) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final colors = context.componentColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ctaColor = isDark ? colors.primary : colors.primaryDark;
    final textDirection = Directionality.of(context);

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: _maxTextScaleFactor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final titleWidth = math
                .min(
                  _titleMaxWidth,
                  constraints.maxWidth -
                      _contentLeftPadding -
                      _closeTextReservedWidth,
                )
                .clamp(120.0, _titleMaxWidth);
            final bodyTextWidth = math
                .min(
                  _bodyTextMaxWidth,
                  constraints.maxWidth -
                      _contentLeftPadding -
                      _duckTextReservedWidth,
                )
                .clamp(120.0, _bodyTextMaxWidth);

            return GestureDetector(
              onTap: _onGetStarted,
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: _bannerHeight),
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_cardRadius),
                  color: colors.fillLight,
                  border: Border.all(color: colors.strokeFaint),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: _duckRightInset,
                      bottom: _duckBottomInset,
                      child: IgnorePointer(
                        child: Image.asset(
                          "assets/ducky_10gb_free.png",
                          width: _duckWidth,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        _contentLeftPadding,
                        _contentTopPadding,
                        16,
                        _contentBottomPadding,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight:
                              _bannerHeight -
                              _contentTopPadding -
                              _contentBottomPadding,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: titleWidth),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.offlineHomeSignupBannerTitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyles.large.copyWith(
                                    color: colors.textBase,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: bodyTextWidth,
                                  ),
                                  child: Text(
                                    l10n.offlineHomeSignupBannerDescription,
                                    style: TextStyles.mini.copyWith(
                                      color: colors.textLight,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: bodyTextWidth,
                                  ),
                                  child: GestureDetector(
                                    onTap: _onGetStarted,
                                    behavior: HitTestBehavior.opaque,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 2,
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment:
                                            AlignmentDirectional.centerStart,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              l10n.offlineHomeSignupBannerAction,
                                              style: TextStyles.bodyBold
                                                  .copyWith(color: ctaColor),
                                            ),
                                            const SizedBox(width: _ctaIconGap),
                                            Text(
                                              textDirection == TextDirection.rtl
                                                  ? "\u2190"
                                                  : "\u2192",
                                              style: TextStyles.bodyBold
                                                  .copyWith(color: ctaColor),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: _closeInset,
                      right: _closeInset,
                      child: IconButtonComponent(
                        tooltip: l10n.close,
                        variant: IconButtonComponentVariant.circular,
                        shouldSurfaceExecutionStates: false,
                        onTap: _onDismiss,
                        icon: const HugeIcon(
                          icon: HugeIcons.strokeRoundedCancel01,
                          size: IconSizes.small,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _onDismiss() async {
    setState(() {
      _dismissed = true;
    });
    await localSettings.setLocalGalleryGetStartedBannerDismissed(true);
  }

  Future<void> _onGetStarted() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const EmailEntryPage(
          showReferralSourceField: false,
          referralSource: "Offline",
        ),
      ),
    );
  }
}

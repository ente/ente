import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/ui/settings/data/import_page.dart';
import 'package:ente_auth/utils/navigation_util.dart' as auth_nav;
import 'package:ente_auth/utils/platform_util.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class HomeEmptyStateWidget extends StatelessWidget {
  final VoidCallback? onScanTap;
  final VoidCallback? onImportImageTap;
  final VoidCallback? onManuallySetupTap;

  const HomeEmptyStateWidget({
    super.key,
    required this.onScanTap,
    required this.onImportImageTap,
    required this.onManuallySetupTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.componentColors;
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final bgSvgPath = isDarkTheme
        ? 'assets/svg/empty-state-bg-dark.svg'
        : 'assets/svg/empty-state-bg-light.svg';
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final extraBottomPadding = PlatformDetector.isMobile()
        ? (bottomPadding > 0 ? bottomPadding : 24.0)
        : 24.0;

    return Semantics(
      container: true,
      identifier: 'auth_empty_state',
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: EdgeInsets.only(
                left: Spacing.xl,
                right: Spacing.xl,
                top: Spacing.xl,
                bottom: extraBottomPadding,
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 188,
                          child: Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                bottom: 6,
                                child: SvgPicture.asset(
                                  bgSvgPath,
                                  width: 224,
                                  height: 142,
                                ),
                              ),
                              Image.asset(
                                'assets/onboarding-2.png',
                                height: 188,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: Spacing.xxl),
                        SizedBox(
                          width: 240,
                          child: Text(
                            l10n.setupFirstAccount,
                            textAlign: TextAlign.center,
                            style: TextStyles.h1.copyWith(
                              color: colors.textBase,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Spacing.xxl),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (PlatformDetector.isMobile()) ...[
                            Semantics(
                              button: true,
                              identifier: 'auth_empty_scan',
                              child: ButtonComponent(
                                label: l10n.importScanQrCode,
                                onTap: onScanTap,
                              ),
                            ),
                          ] else ...[
                            Semantics(
                              button: true,
                              identifier: 'auth_empty_gallery',
                              child: ButtonComponent(
                                label: l10n.importFromGallery,
                                onTap: onImportImageTap,
                              ),
                            ),
                          ],
                          const SizedBox(height: Spacing.md),
                          Semantics(
                            button: true,
                            identifier: 'auth_empty_manual_setup',
                            child: ButtonComponent(
                              label: l10n.importEnterSetupKey,
                              variant: ButtonComponentVariant.secondary,
                              onTap: onManuallySetupTap,
                            ),
                          ),
                          const SizedBox(height: Spacing.sm),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              ButtonComponent(
                                label: l10n.importCodes,
                                size: ButtonComponentSize.small,
                                variant: ButtonComponentVariant.link,
                                onTap: () {
                                  auth_nav.routeToPage(
                                    context,
                                    const ImportCodePage(),
                                  );
                                },
                              ),
                              ButtonComponent(
                                label: l10n.faq,
                                size: ButtonComponentSize.small,
                                variant: ButtonComponentVariant.link,
                                onTap: () {
                                  PlatformUtil.openUrlInBrowser(
                                    'https://ente.com/help/auth/faq',
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

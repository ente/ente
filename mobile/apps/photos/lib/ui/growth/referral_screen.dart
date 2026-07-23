import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/gateways/storage_bonus/models/storage_bonus.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/user_details.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/account/user_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/theme/text_style.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/common/web_page.dart";
import "package:photos/ui/components/menu_item_widget/menu_item_widget_new.dart";
import "package:photos/ui/growth/apply_code_sheet.dart";
import "package:photos/ui/growth/referral_code_widget.dart";
import "package:photos/ui/growth/storage_details_screen.dart";
import "package:photos/utils/share_util.dart";
import "package:tuple/tuple.dart";

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  bool canApplyCode = true;

  void _safeUIUpdate() {
    if (mounted) {
      setState(() => {});
    }
  }

  Future<Tuple2<ReferralView, UserDetails>> _fetchData() async {
    UserDetails? cachedUserDetails = UserService.instance
        .getCachedUserDetails();
    cachedUserDetails ??= await UserService.instance.getUserDetailsV2(
      memoryCount: false,
    );
    final referralView = await storageBonusService.getReferralView();
    return Tuple2(referralView, cachedUserDetails);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);

    return Scaffold(
      backgroundColor: colorScheme.backgroundColour,
      body: SafeArea(
        child: FutureBuilder<Tuple2<ReferralView, UserDetails>>(
          future: _fetchData(),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return ReferralWidget(
                referralView: snapshot.data!.item1,
                userDetails: snapshot.data!.item2,
                notifyParent: _safeUIUpdate,
              );
            } else if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Icon(
                        Icons.arrow_back,
                        color: colorScheme.strokeBase,
                        size: 24,
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          AppLocalizations.of(
                            context,
                          ).failedToFetchReferralDetails,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            return const Center(child: EnteLoadingWidget());
          },
        ),
      ),
    );
  }
}

class ReferralWidget extends StatelessWidget {
  final ReferralView referralView;
  final UserDetails userDetails;
  final Function notifyParent;

  const ReferralWidget({
    required this.referralView,
    required this.userDetails,
    required this.notifyParent,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bool isReferralEnabled = referralView.planInfo.isEnabled;

    final cardColor = isDarkMode
        ? const Color(0xFF212121)
        : const Color(0xFFFFFFFF);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            // Back arrow
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Icon(
                Icons.arrow_back,
                color: colorScheme.strokeBase,
                size: 24,
              ),
            ),
            const SizedBox(height: 24),
            // Header section with title and share button
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context).earnFreeStorage,
                        style: textTheme.largeBold,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppLocalizations.of(context).shareCodeEarnStorage,
                        style: textTheme.miniMuted,
                      ),
                    ],
                  ),
                ),
                if (isReferralEnabled)
                  GestureDetector(
                    onTap: () {
                      shareText(
                        AppLocalizations.of(context).shareTextReferralCode(
                          referralCode: referralView.code,
                          referralStorageInGB:
                              referralView.planInfo.storageInGB,
                        ),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedShare08,
                        color: colorScheme.strokeBase,
                        size: 20,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 42),
            // Referral code section
            if (isReferralEnabled) ...[
              Center(
                child: ReferralCodeWidget(
                  referralView.code,
                  shouldShowEdit: true,
                  userDetails: userDetails,
                  notifyParent: notifyParent,
                ),
              ),
              const SizedBox(height: 16),
              // Instructions
              _buildInstructions(context, textTheme),
              const SizedBox(height: 16),
            ] else ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, color: colorScheme.strokeMuted),
                      const SizedBox(height: 12),
                      Text(
                        AppLocalizations.of(
                          context,
                        ).referralsAreCurrentlyPaused,
                        style: textTheme.small.copyWith(
                          color: colorScheme.textFaint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            // Menu items
            if (referralView.enableApplyCode) ...[
              MenuItemWidgetNew(
                title: AppLocalizations.of(context).applyCodeTitle,
                trailingIcon: Icons.chevron_right_outlined,
                trailingIconIsMuted: true,
                onTap: () async {
                  final result = await showApplyCodeSheet(
                    context,
                    referralView: referralView,
                    userDetails: userDetails,
                  );
                  if (result == true) {
                    notifyParent();
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
            MenuItemWidgetNew(
              title: AppLocalizations.of(context).faq,
              trailingIcon: Icons.chevron_right_outlined,
              trailingIconIsMuted: true,
              onTap: () async {
                await routeToPage(
                  context,
                  WebPage(
                    AppLocalizations.of(context).faq,
                    "https://ente.com/help/photos/features/account/referral-program/",
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            MenuItemWidgetNew(
              title: AppLocalizations.of(context).details,
              trailingIcon: Icons.chevron_right_outlined,
              trailingIconIsMuted: true,
              onTap: () async {
                await routeToPage(
                  context,
                  StorageDetailsScreen(referralView, userDetails),
                );
              },
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructions(BuildContext context, EnteTextTheme textTheme) {
    const greenColor = Color(0xFF08C225);
    final storageInGB = referralView.planInfo.storageInGB;
    final mutedStyle = textTheme.miniMuted.copyWith(height: 2);
    final step3Text = AppLocalizations.of(
      context,
    ).referralStep3(storageInGB: storageInGB);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppLocalizations.of(context).referralStep1, style: mutedStyle),
        Text(AppLocalizations.of(context).referralStep2, style: mutedStyle),
        RichText(
          text: TextSpan(
            style: mutedStyle,
            children: _buildHighlightedSpans(
              step3Text,
              mutedStyle,
              greenColor,
              ["${storageInGB}GB free", "$storageInGB GB free"],
              ["${storageInGB}GB", "$storageInGB GB"],
            ),
          ),
        ),
      ],
    );
  }

  List<TextSpan> _buildHighlightedSpans(
    String text,
    TextStyle baseStyle,
    Color highlightColor,
    List<String> preferredTokens,
    List<String> fallbackTokens,
  ) {
    final tokens = preferredTokens.any(text.contains)
        ? preferredTokens
        : fallbackTokens.any(text.contains)
        ? fallbackTokens
        : const <String>[];

    if (tokens.isEmpty) {
      return [TextSpan(text: text)];
    }

    final spans = <TextSpan>[];
    var index = 0;

    while (index < text.length) {
      int? nextIndex;
      String? nextToken;
      for (final token in tokens) {
        final tokenIndex = text.indexOf(token, index);
        if (tokenIndex == -1) {
          continue;
        }
        if (nextIndex == null || tokenIndex < nextIndex) {
          nextIndex = tokenIndex;
          nextToken = token;
        }
      }

      if (nextIndex == null || nextToken == null) {
        break;
      }

      if (nextIndex > index) {
        spans.add(TextSpan(text: text.substring(index, nextIndex)));
      }

      spans.add(
        TextSpan(
          text: nextToken,
          style: baseStyle.copyWith(color: highlightColor),
        ),
      );

      index = nextIndex + nextToken.length;
    }

    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index)));
    }

    return spans;
  }
}

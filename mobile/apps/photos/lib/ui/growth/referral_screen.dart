import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/loading_widget.dart";
import "package:flutter/material.dart";
import "package:photos/gateways/storage_bonus/models/storage_bonus.dart";
import "package:photos/models/user_details.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/account/user_service.dart";
import "package:photos/ui/common/web_page.dart";
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
  void _safeUIUpdate() {
    if (mounted) {
      setState(() {});
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
    final l10n = context.strings;
    return FutureBuilder<Tuple2<ReferralView, UserDetails>>(
      future: _fetchData(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return SettingsPageScaffold(
            title: l10n.earnFreeStorage,
            subtitle: l10n.shareCodeEarnStorage,
            children: [
              ReferralWidget(
                referralView: snapshot.data!.item1,
                userDetails: snapshot.data!.item2,
                notifyParent: _safeUIUpdate,
              ),
            ],
          );
        } else if (snapshot.hasError) {
          return Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Icon(
                        Icons.arrow_back,
                        color: context.componentColors.iconColor,
                        size: 24,
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          l10n.failedToFetchReferralDetails,
                          style: TextStyles.body.copyWith(
                            color: context.componentColors.textLight,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return const Scaffold(
          body: SafeArea(child: Center(child: EnteLoadingWidget())),
        );
      },
    );
  }
}

class ReferralWidget extends StatelessWidget {
  final ReferralView referralView;
  final UserDetails userDetails;
  final VoidCallback notifyParent;

  const ReferralWidget({
    required this.referralView,
    required this.userDetails,
    required this.notifyParent,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final l10n = context.strings;
    final bool isReferralEnabled = referralView.planInfo.isEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isReferralEnabled) ...[
          const SizedBox(height: Spacing.xxl),
          ReferralCodeWidget(
            code: referralView.code,
            userDetails: userDetails,
            onCodeChanged: (code) {
              referralView.code = code;
              notifyParent();
            },
          ),
          const SizedBox(height: Spacing.md),
          _buildInstructions(context),
          const SizedBox(height: Spacing.md),
          ButtonComponent(
            label: l10n.share,
            density: ButtonComponentDensity.compact,
            shouldSurfaceExecutionStates: false,
            onTap: () {
              shareText(
                l10n.shareTextReferralInvite(referralCode: referralView.code),
              );
            },
          ),
          const SizedBox(height: 40),
        ] else ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.error_outline, color: colors.textLight),
                  const SizedBox(height: Spacing.md),
                  Text(
                    l10n.referralsAreCurrentlyPaused,
                    style: TextStyles.body.copyWith(color: colors.textLight),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (referralView.enableApplyCode) ...[
          MenuComponent(
            title: l10n.applyCodeTitle,
            trailing: _chevron(colors),
            onTap: () async {
              final result = await showApplyCodeSheet(
                context,
                referralView: referralView,
                userDetails: userDetails,
              );
              if (result == true) notifyParent();
            },
          ),
          const SizedBox(height: Spacing.sm),
        ],
        MenuComponent(
          title: l10n.details,
          trailing: _chevron(colors),
          onTap: () async {
            await routeToPage(
              context,
              StorageDetailsScreen(referralView, userDetails),
            );
          },
        ),
        const SizedBox(height: Spacing.sm),
        MenuComponent(
          title: l10n.faqs,
          trailing: _chevron(colors),
          onTap: () async {
            await routeToPage(
              context,
              WebPage(
                l10n.faqs,
                "https://ente.com/help/photos/features/account/referral-program/",
              ),
            );
          },
        ),
        const SizedBox(height: Spacing.xxl),
      ],
    );
  }

  Widget _chevron(ColorTokens colors) => Icon(
    Icons.chevron_right_outlined,
    color: colors.textLight,
    size: IconSizes.medium,
  );

  Widget _buildInstructions(BuildContext context) {
    final colors = context.componentColors;
    final storageInGB = referralView.planInfo.storageInGB;
    final mutedStyle = TextStyles.mini.copyWith(
      color: colors.textLight,
      height: 2,
    );

    final highlightTokens = [
      "$storageInGB GB free",
      "${storageInGB}GB free",
      "$storageInGB GB",
      "${storageInGB}GB",
    ];

    Widget step(String text) => Text.rich(
      TextSpan(
        style: mutedStyle,
        children: _buildHighlightedSpans(
          text,
          mutedStyle,
          colors.textBase,
          highlightTokens,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.strings.referralStep1, style: mutedStyle),
        step(context.strings.referralStep2(storageInGB: storageInGB)),
        step(context.strings.referralStep3(storageInGB: storageInGB)),
      ],
    );
  }

  List<TextSpan> _buildHighlightedSpans(
    String text,
    TextStyle baseStyle,
    Color highlightColor,
    List<String> tokens,
  ) {
    if (!tokens.any(text.contains)) {
      return [TextSpan(text: text)];
    }

    final highlightStyle = baseStyle.copyWith(
      color: highlightColor,
      fontWeight: FontWeight.w600,
    );
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

      spans.add(TextSpan(text: nextToken, style: highlightStyle));

      index = nextIndex + nextToken.length;
    }

    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index)));
    }

    return spans;
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photos/gateways/billing/models/billing_plan.dart';
import 'package:photos/gateways/billing/models/subscription.dart';
import 'package:photos/generated/l10n.dart';
import 'package:photos/models/user_details.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/family_service.dart';
import 'package:photos/theme/ente_theme.dart';
import 'package:photos/theme/text_style.dart';
import 'package:photos/ui/components/base_bottom_sheet.dart';
import 'package:photos/ui/components/buttons/button_widget_v2.dart';
import 'package:photos/ui/family/edit_storage_limit_page.dart';
import 'package:photos/ui/family/family_ui.dart';
import 'package:photos/ui/family/invite_members_page.dart';
import 'package:photos/ui/payment/subscription.dart';
import 'package:photos/utils/avatar_util.dart';
import 'package:photos/utils/dialog_util.dart';

class FamilyPlanPage extends StatefulWidget {
  const FamilyPlanPage({
    required this.initialUserDetails,
    this.popOnFreeAdvertViewPlans = false,
    this.refreshOnOpen = true,
    super.key,
  });

  final UserDetails initialUserDetails;
  final bool popOnFreeAdvertViewPlans;
  final bool refreshOnOpen;

  @override
  State<FamilyPlanPage> createState() => _FamilyPlanPageState();
}

class _FamilyPlanPageState extends State<FamilyPlanPage> {
  static const String _advertIllustrationAsset =
      "assets/family_plan_illustration.png";
  static const double _advertContentWidth = 300;
  static const double _advertBalancedMinHeight = 560;

  late UserDetails _userDetails = widget.initialUserDetails;
  String? _startingPrice;
  bool _isRefreshing = false;

  bool get _isFreeUser =>
      _userDetails.subscription.productID == freeProductID &&
      !_userDetails.hasPaidAddon();

  bool get _isFamilyAdmin =>
      _userDetails.currentFamilyMember()?.isAdmin ?? false;

  bool get _isFamilyMember => _userDetails.isPartOfFamily() && !_isFamilyAdmin;

  bool get _showsAdminDashboard =>
      _isFamilyAdmin && _userDetails.hasConfiguredFamily();

  bool get _showsMemberDashboard => _isFamilyMember;

  bool get _showsDashboard => _showsAdminDashboard || _showsMemberDashboard;

  int get _remainingSlots {
    final memberCount =
        _userDetails.familyData?.members
            ?.where(
              (member) => member.email.trim() != _userDetails.email.trim(),
            )
            .length ??
        0;
    return math.max(0, 5 - memberCount);
  }

  @override
  void initState() {
    super.initState();
    if (widget.refreshOnOpen) {
      unawaited(_refreshUserDetails());
    }
    if (_isFreeUser && !_userDetails.isPartOfFamily()) {
      unawaited(_loadStartingPrice());
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _showsAdminDashboard
        ? _buildDashboard(context, isAdminView: true)
        : _showsMemberDashboard
        ? _buildDashboard(context, isAdminView: false)
        : _isFreeUser
        ? _buildFreeAdvert(context)
        : _buildPaidAdvert(context);

    return FamilyPageScaffold(
      title: _showsDashboard ? AppLocalizations.of(context).family : null,
      child: content,
    );
  }

  Widget _buildFreeAdvert(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _buildAdvert(
      context,
      illustrationAsset: _advertIllustrationAsset,
      title: l10n.designedForFamilies,
      body: l10n.shareYourSubscription,
      benefits: [
        _BenefitItem(
          icon: Icons.group_outlined,
          text: l10n.shareStorageWith5Members,
        ),
        _BenefitItem(
          icon: Icons.lock_outline,
          text: l10n.privateSpaceForEveryMember,
        ),
        _BenefitItem(
          icon: Icons.forum_outlined,
          text: l10n.feedToEngageWithFamily,
        ),
      ],
      footerText: _startingPrice == null
          ? null
          : l10n.plansStartAt(price: _startingPrice!),
      buttonLabel: l10n.viewPlans,
      onButtonTap: () async {
        if (widget.popOnFreeAdvertViewPlans && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
          return;
        }
        await routeToPage(context, getSubscriptionPage());
      },
    );
  }

  Widget _buildPaidAdvert(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _buildAdvert(
      context,
      illustrationAsset: _advertIllustrationAsset,
      title: l10n.bringYourFamilyAlong,
      body: l10n.yourPlanSupportsFamily,
      benefits: [
        _BenefitItem(
          icon: Icons.group_add_outlined,
          text: l10n.addUpTo5MembersFree,
        ),
        _BenefitItem(
          icon: Icons.lock_outline,
          text: l10n.privateSpaceForEveryMember,
        ),
        _BenefitItem(
          icon: Icons.forum_outlined,
          text: l10n.feedToEngageWithFamily,
        ),
      ],
      buttonLabel: l10n.addFamilyMember,
      onButtonTap: () async {
        unawaited(_openInvitePage());
      },
    );
  }

  Widget _buildAdvert(
    BuildContext context, {
    required String illustrationAsset,
    required String title,
    required String body,
    required List<Widget> benefits,
    required String buttonLabel,
    required Future<void> Function() onButtonTap,
    String? footerText,
  }) {
    final textTheme = getEnteTextTheme(context);
    final heroSection = _buildAdvertHero(
      illustrationAsset: illustrationAsset,
      title: title,
      body: body,
    );
    final benefitsSection = _buildAdvertBenefits(benefits);
    final footerSection = _buildAdvertFooter(
      textTheme: textTheme,
      footerText: footerText,
      buttonLabel: buttonLabel,
      onButtonTap: onButtonTap,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight < _advertBalancedMinHeight) {
          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      heroSection,
                      const SizedBox(height: 28),
                      benefitsSection,
                    ],
                  ),
                ),
              ),
              footerSection,
            ],
          );
        }

        return Column(
          children: [
            Expanded(flex: 9, child: Center(child: heroSection)),
            Expanded(
              flex: 5,
              child: Align(
                alignment: Alignment.topCenter,
                child: benefitsSection,
              ),
            ),
            Expanded(
              flex: footerText != null ? 4 : 3,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: footerSection,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAdvertHero({
    required String illustrationAsset,
    required String title,
    required String body,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _advertContentWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            Center(
              child: Image.asset(
                illustrationAsset,
                width: 200,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 20),
            _AdvertTitle(text: title),
            const SizedBox(height: 12),
            _AdvertBody(text: body),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvertBenefits(List<Widget> benefits) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _advertContentWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: benefits,
        ),
      ),
    );
  }

  Widget _buildAdvertFooter({
    required EnteTextTheme textTheme,
    required String? footerText,
    required String buttonLabel,
    required Future<void> Function() onButtonTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (footerText != null) ...[
          Text(
            footerText,
            textAlign: TextAlign.center,
            style: textTheme.smallFaint,
          ),
          const SizedBox(height: 16),
        ] else
          const SizedBox(height: 16),
        ButtonWidgetV2(
          buttonType: ButtonTypeV2.primary,
          labelText: buttonLabel,
          onTap: onButtonTap,
        ),
      ],
    );
  }

  Widget _buildDashboard(BuildContext context, {required bool isAdminView}) {
    final l10n = AppLocalizations.of(context);
    final members = _sortedMembersForDashboard(isAdminView: isAdminView);
    final activeMembers = members.where((member) => member.isActive).toList();
    final colorMap = _memberColorMap(members);

    final currentEmail = _userDetails.email.trim().toLowerCase();
    final currentMember = members.firstWhereOrNull(
      (m) => m.email.trim().toLowerCase() == currentEmail,
    );
    final storageLimit = !isAdminView ? currentMember?.storageLimit : null;

    return ListView(
      children: [
        _FamilyStorageOverviewCard(
          userDetails: _userDetails,
          members: activeMembers,
          colorMap: colorMap,
          storageLimit: storageLimit,
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            l10n.members,
            style: getEnteTextTheme(context).smallMuted,
          ),
        ),
        _FamilyMembersCard(
          members: members,
          userDetails: _userDetails,
          memberColor: _memberColor,
          isAdminView: isAdminView,
          onMemberTap: _showMemberActions,
        ),
        const SizedBox(height: 24),
        if (isAdminView) ...[
          if (_remainingSlots > 0) ...[
            ButtonWidgetV2(
              buttonType: ButtonTypeV2.primary,
              labelText: l10n.addMember,
              leadingWidget: const Icon(
                Icons.person_add_outlined,
                color: Colors.white,
                size: 20,
              ),
              onTap: () async {
                unawaited(_openInvitePage());
              },
            ),
            const SizedBox(height: 12),
          ],
          ButtonWidgetV2(
            buttonType: ButtonTypeV2.tertiaryCritical,
            labelText: l10n.closeFamilyPlan,
            onTap: () async {
              unawaited(_confirmCloseFamily());
            },
          ),
        ] else ...[
          ButtonWidgetV2(
            buttonType: ButtonTypeV2.tertiaryCritical,
            labelText: l10n.leaveFamilyPlan,
            onTap: () async {
              unawaited(_confirmLeaveFamily());
            },
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _loadStartingPrice() async {
    try {
      final billingPlans = await billingService.getBillingPlans();
      final cheapestPlan = billingPlans.plans
          .where((plan) => plan.id != freeProductID && plan.price.isNotEmpty)
          .map(_monthlyPriceForPlan)
          .whereType<_MonthlyPrice>()
          .sorted((a, b) => a.value.compareTo(b.value))
          .firstOrNull;
      if (mounted && cheapestPlan != null) {
        setState(() => _startingPrice = cheapestPlan.displayPrice);
      }
    } catch (_) {}
  }

  Future<void> _refreshUserDetails({bool showError = false}) async {
    if (_isRefreshing) {
      return;
    }
    setState(() => _isRefreshing = true);
    try {
      final details = await FamilyService.instance.refreshUserDetails();
      if (!mounted) {
        return;
      }
      setState(() => _userDetails = details);
    } catch (error) {
      if (mounted && showError) {
        await showGenericErrorDialog(context: context, error: error);
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<void> _openInvitePage() async {
    final result = await routeToPage<InviteMembersPageResult>(
      context,
      InviteMembersPage(
        userDetails: _userDetails,
        remainingSlots: _remainingSlots,
      ),
    );
    await _refreshUserDetails();
    if (!mounted) {
      return;
    }
    if (result?.invitesSent ?? false) {
      showFamilySnackBar(
        context,
        AppLocalizations.of(context).invitesSentCount(count: result!.sentCount),
      );
    }
  }

  Future<void> _showMemberActions(FamilyMember member) async {
    final isCurrentUser = member.email.trim() == _userDetails.email.trim();
    if (!_isFamilyAdmin || isCurrentUser) {
      return;
    }

    final l10n = AppLocalizations.of(context);
    final colorScheme = getEnteColorScheme(context);
    await showBaseBottomSheet<void>(
      context,
      title: member.email,
      titleStyle: getEnteTextTheme(context).large,
      headerSpacing: 16,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      topCornerRadius: 24,
      modalBackgroundColor: Colors.transparent,
      closeButtonBackgroundColor: colorScheme.fillFaint,
      closeButtonSize: 36,
      closeIconSize: 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActionGroup(
            children: member.isPending
                ? [
                    _ActionTile(
                      icon: Icons.send_outlined,
                      title: l10n.resendInvite,
                      onTap: () async {
                        Navigator.of(context).pop();
                        await _resendInvite(member);
                      },
                    ),
                    _ActionTile(
                      icon: Icons.link_off_outlined,
                      title: l10n.revokeInvite,
                      isDestructive: true,
                      onTap: () async {
                        Navigator.of(context).pop();
                        await _confirmRevokeInvite(member);
                      },
                    ),
                  ]
                : [
                    _ActionTile(
                      icon: Icons.tune,
                      title: l10n.editStorageLimit,
                      subtitle: member.storageLimit == null
                          ? l10n.noLimitSet
                          : convertBytesToReadableFormat(member.storageLimit!),
                      trailingChevron: true,
                      onTap: () async {
                        Navigator.of(context).pop();
                        final updatedUserDetails =
                            await routeToPage<UserDetails>(
                              context,
                              EditStorageLimitPage(
                                member: member,
                                totalStorageInBytes: _userDetails
                                    .getTotalStorage(),
                                avatarColor: _memberColor(member),
                              ),
                            );
                        if (!mounted) {
                          return;
                        }
                        if (updatedUserDetails != null) {
                          setState(() => _userDetails = updatedUserDetails);
                        } else {
                          await _refreshUserDetails();
                        }
                      },
                    ),
                    _ActionTile(
                      icon: Icons.person_remove_outlined,
                      title: l10n.removeFromFamily,
                      isDestructive: true,
                      onTap: () async {
                        Navigator.of(context).pop();
                        await _confirmRemoveMember(member);
                      },
                    ),
                  ],
          ),
        ],
      ),
    );
  }

  Future<void> _resendInvite(FamilyMember member) async {
    try {
      await FamilyService.instance.resendInvite(member);
      await _refreshUserDetails();
      if (mounted) {
        showFamilySnackBar(context, AppLocalizations.of(context).inviteResent);
      }
    } catch (error) {
      if (mounted) {
        await showGenericErrorDialog(context: context, error: error);
      }
    }
  }

  Future<void> _confirmRemoveMember(FamilyMember member) async {
    final confirmed = await showFamilyConfirmationSheet(
      context,
      title: AppLocalizations.of(context).removeMemberConfirmTitle,
      body: AppLocalizations.of(
        context,
      ).removeMemberConfirmBody(email: member.email),
      actionLabel: AppLocalizations.of(context).remove,
    );
    if (!confirmed || !mounted) {
      return;
    }

    try {
      await FamilyService.instance.removeMember(member);
      await _refreshUserDetails();
    } catch (error) {
      if (mounted) {
        await showGenericErrorDialog(context: context, error: error);
      }
    }
  }

  Future<void> _confirmRevokeInvite(FamilyMember member) async {
    final confirmed = await showFamilyConfirmationSheet(
      context,
      title: AppLocalizations.of(context).revokeInviteConfirmTitle,
      body: AppLocalizations.of(
        context,
      ).revokeInviteConfirmBody(email: member.email),
      actionLabel: AppLocalizations.of(context).revoke,
    );
    if (!confirmed || !mounted) {
      return;
    }

    try {
      await FamilyService.instance.revokeInvite(member);
      await _refreshUserDetails();
    } catch (error) {
      if (mounted) {
        await showGenericErrorDialog(context: context, error: error);
      }
    }
  }

  Future<void> _confirmCloseFamily() async {
    final confirmed = await showFamilyConfirmationSheet(
      context,
      title: AppLocalizations.of(context).closeFamilyConfirmTitle,
      body: AppLocalizations.of(context).closeFamilyConfirmBody,
      actionLabel: AppLocalizations.of(context).closeFamilyPlan,
    );
    if (!confirmed || !mounted) {
      return;
    }

    try {
      await FamilyService.instance.closeFamily(_userDetails);
      await _refreshUserDetails();
    } catch (error) {
      if (mounted) {
        await showGenericErrorDialog(context: context, error: error);
      }
    }
  }

  Future<void> _confirmLeaveFamily() async {
    final confirmed = await showFamilyConfirmationSheet(
      context,
      title: AppLocalizations.of(context).leaveFamily,
      body: AppLocalizations.of(context).areYouSureThatYouWantToLeaveTheFamily,
      actionLabel: AppLocalizations.of(context).leave,
    );
    if (!confirmed || !mounted) {
      return;
    }

    try {
      await FamilyService.instance.leaveFamily();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        await showGenericErrorDialog(context: context, error: error);
      }
    }
  }

  List<FamilyMember> _sortedMembersForDashboard({required bool isAdminView}) {
    final members = List<FamilyMember>.from(
      _userDetails.familyData?.members ?? const <FamilyMember>[],
    );
    final currentEmail = _userDetails.email.trim().toLowerCase();

    if (!isAdminView) {
      members.removeWhere((member) => !member.isActive);
    }

    members.sort((a, b) {
      if (a.email.trim().toLowerCase() == currentEmail) return -1;
      if (b.email.trim().toLowerCase() == currentEmail) return 1;
      if (isAdminView && a.isPending != b.isPending) {
        return a.isPending ? 1 : -1;
      }
      if (a.isAdmin != b.isAdmin) return a.isAdmin ? -1 : 1;
      return a.email.compareTo(b.email);
    });
    return members;
  }

  Map<String, Color> _memberColorMap(List<FamilyMember> members) {
    return {for (final member in members) member.email: _memberColor(member)};
  }

  Color _memberColor(FamilyMember member) {
    return avatarBackgroundColor(
      context,
      AvatarIdentity.account(
        label: member.email,
        email: member.email,
        userID: null,
        currentUserEmail: _userDetails.email,
      ),
    );
  }

  _MonthlyPrice? _monthlyPriceForPlan(BillingPlan plan) {
    if (plan.price.isEmpty) {
      return null;
    }
    if (plan.price.length < 2) {
      return _MonthlyPrice(plan.price, double.infinity);
    }

    final currencySymbol = plan.price[0];
    final rawPrice = plan.price.substring(1).replaceAll(",", "");
    final parsedPrice = double.tryParse(rawPrice);
    if (parsedPrice == null) {
      return null;
    }

    final monthlyValue = plan.period == "year" ? parsedPrice / 12 : parsedPrice;
    var displayValue = monthlyValue.toStringAsFixed(2);
    if (displayValue.endsWith(".00")) {
      displayValue = displayValue.substring(0, displayValue.length - 3);
    }
    return _MonthlyPrice("$currencySymbol$displayValue", monthlyValue);
  }
}

class _AdvertTitle extends StatelessWidget {
  const _AdvertTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: getEnteTextTheme(context).h3Bold,
      textAlign: TextAlign.center,
    );
  }
}

class _AdvertBody extends StatelessWidget {
  const _AdvertBody({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: getEnteTextTheme(context).bodyMuted.copyWith(height: 1.5),
      textAlign: TextAlign.center,
    );
  }
}

class _BenefitItem extends StatelessWidget {
  const _BenefitItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colorScheme.greenBase),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: getEnteTextTheme(
                context,
              ).body.copyWith(fontSize: 15, height: 21 / 15),
            ),
          ),
        ],
      ),
    );
  }
}

class _FamilyStorageOverviewCard extends StatelessWidget {
  const _FamilyStorageOverviewCard({
    required this.userDetails,
    required this.members,
    required this.colorMap,
    this.storageLimit,
  });

  final UserDetails userDetails;
  final List<FamilyMember> members;
  final Map<String, Color> colorMap;
  final int? storageLimit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final l10n = AppLocalizations.of(context);
    final totalUsed =
        userDetails.familyData?.getTotalUsage() ?? userDetails.usage;
    final totalStorage = userDetails.getTotalStorage();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.fill,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(l10n.storage, style: textTheme.bodyBold),
              Text(
                l10n.storageUsedOfTotal(
                  used: convertBytesToReadableFormat(totalUsed),
                  total: convertBytesToReadableFormat(totalStorage),
                ),
                style: textTheme.smallMuted,
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 14,
            child: LayoutBuilder(
              builder: (context, constraints) {
                var currentLeft = 0.0;
                final segmentWidgets = <Widget>[];
                for (final member in members) {
                  final width = totalStorage == 0
                      ? 0.0
                      : constraints.maxWidth * (member.usage / totalStorage);
                  if (width <= 0) {
                    continue;
                  }
                  segmentWidgets.add(
                    Positioned(
                      left: currentLeft,
                      child: Container(
                        width: width,
                        height: 14,
                        color: colorMap[member.email] ?? colorScheme.primary500,
                      ),
                    ),
                  );
                  currentLeft += width;
                }

                return ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Stack(
                    children: [
                      Container(color: colorScheme.fillMuted),
                      ...segmentWidgets,
                    ],
                  ),
                );
              },
            ),
          ),
          if (storageLimit != null) ...[
            const SizedBox(height: 10),
            Text(
              AppLocalizations.of(context).yourStorageIsLimitedTo(
                limit: convertBytesToReadableFormat(storageLimit!),
              ),
              style: textTheme.miniMuted,
            ),
          ],
        ],
      ),
    );
  }
}

class _FamilyMembersCard extends StatefulWidget {
  const _FamilyMembersCard({
    required this.members,
    required this.userDetails,
    required this.memberColor,
    required this.isAdminView,
    required this.onMemberTap,
  });

  final List<FamilyMember> members;
  final UserDetails userDetails;
  final Color Function(FamilyMember) memberColor;
  final bool isAdminView;
  final ValueChanged<FamilyMember> onMemberTap;

  @override
  State<_FamilyMembersCard> createState() => _FamilyMembersCardState();
}

class _FamilyMembersCardState extends State<_FamilyMembersCard> {
  static const _animationDuration = Duration(milliseconds: 200);

  final _listKey = GlobalKey<AnimatedListState>();
  late List<FamilyMember> _displayedMembers = List<FamilyMember>.from(
    widget.members,
  );

  @override
  void didUpdateWidget(covariant _FamilyMembersCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMembers();
  }

  void _syncMembers() {
    final nextMembers = List<FamilyMember>.from(widget.members);
    final nextMembersById = {
      for (final member in nextMembers) member.id: member,
    };
    final currentMemberIds = {
      for (final member in _displayedMembers) member.id,
    };
    final currentSharedOrder = _displayedMembers
        .where((member) => nextMembersById.containsKey(member.id))
        .map((member) => member.id)
        .toList();
    final nextSharedOrder = nextMembers
        .where((member) => currentMemberIds.contains(member.id))
        .map((member) => member.id)
        .toList();

    if (!listEquals(currentSharedOrder, nextSharedOrder) ||
        _listKey.currentState == null) {
      setState(() {
        _displayedMembers = nextMembers;
      });
      return;
    }

    var needsRebuild = false;

    for (var i = _displayedMembers.length - 1; i >= 0; i--) {
      final member = _displayedMembers[i];
      if (nextMembersById.containsKey(member.id)) {
        continue;
      }

      final hadDivider = i != _displayedMembers.length - 1;
      final removedMember = _displayedMembers.removeAt(i);
      needsRebuild = true;
      _listKey.currentState!.removeItem(
        i,
        (context, animation) => _buildAnimatedMemberItem(
          removedMember,
          animation,
          showDivider: hadDivider,
        ),
        duration: _animationDuration,
      );
    }

    for (var i = 0; i < nextMembers.length; i++) {
      final nextMember = nextMembers[i];
      if (i < _displayedMembers.length &&
          _displayedMembers[i].id == nextMember.id) {
        if (!_matchesMemberState(_displayedMembers[i], nextMember)) {
          _displayedMembers[i] = nextMember;
          needsRebuild = true;
        }
        continue;
      }

      final existingIndex = _displayedMembers.indexWhere(
        (member) => member.id == nextMember.id,
      );
      if (existingIndex != -1) {
        setState(() {
          _displayedMembers = nextMembers;
        });
        return;
      }

      _displayedMembers.insert(i, nextMember);
      needsRebuild = true;
      _listKey.currentState!.insertItem(i, duration: _animationDuration);
    }

    if (needsRebuild) {
      setState(() {});
    }
  }

  bool _matchesMemberState(FamilyMember a, FamilyMember b) {
    return a.id == b.id &&
        a.email == b.email &&
        a.usage == b.usage &&
        a.isAdmin == b.isAdmin &&
        a.status == b.status &&
        a.storageLimit == b.storageLimit;
  }

  Widget _buildAnimatedMemberItem(
    FamilyMember member,
    Animation<double> animation, {
    required bool showDivider,
  }) {
    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return FadeTransition(
      opacity: curvedAnimation,
      child: SizeTransition(
        sizeFactor: curvedAnimation,
        axisAlignment: -1,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.04),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: _FamilyMemberListItem(
            member: member,
            currentEmail: widget.userDetails.email,
            avatarColor: widget.memberColor(member),
            isAdminView: widget.isAdminView,
            onTap: () => widget.onMemberTap(member),
            showDivider: showDivider,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);

    return AnimatedSize(
      duration: _animationDuration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.fill,
          borderRadius: BorderRadius.circular(20),
        ),
        child: AnimatedList(
          key: _listKey,
          shrinkWrap: true,
          primary: false,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          initialItemCount: _displayedMembers.length,
          itemBuilder: (context, index, animation) {
            final member = _displayedMembers[index];
            return _buildAnimatedMemberItem(
              member,
              animation,
              showDivider: index != _displayedMembers.length - 1,
            );
          },
        ),
      ),
    );
  }
}

class _FamilyMemberListItem extends StatelessWidget {
  const _FamilyMemberListItem({
    required this.member,
    required this.currentEmail,
    required this.isAdminView,
    required this.onTap,
    required this.showDivider,
    required this.avatarColor,
  });

  final FamilyMember member;
  final String currentEmail;
  final bool isAdminView;
  final VoidCallback onTap;
  final bool showDivider;
  final Color avatarColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FamilyMemberRow(
          member: member,
          currentEmail: currentEmail,
          avatarColor: avatarColor,
          isAdminView: isAdminView,
          onTap: onTap,
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: colorScheme.strokeSolid,
          ),
      ],
    );
  }
}

class _FamilyMemberRow extends StatelessWidget {
  const _FamilyMemberRow({
    required this.member,
    required this.currentEmail,
    required this.isAdminView,
    required this.onTap,
    required this.avatarColor,
  });

  final FamilyMember member;
  final String currentEmail;
  final bool isAdminView;
  final VoidCallback onTap;
  final Color avatarColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final l10n = AppLocalizations.of(context);
    final isCurrentUser =
        member.email.trim().toLowerCase() == currentEmail.trim().toLowerCase();
    final canTap = isAdminView && !isCurrentUser;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: canTap ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: avatarColor,
              child: Text(
                member.email.substring(0, 1).toUpperCase(),
                style: textTheme.bodyBold.copyWith(color: Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.email,
                    style: member.isPending
                        ? textTheme.body.copyWith(color: colorScheme.textMuted)
                        : textTheme.body,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    member.isPending
                        ? l10n.pending
                        : l10n.memberStorageUsed(
                            amount: convertBytesToReadableFormat(member.usage),
                          ),
                    style: textTheme.smallMuted,
                  ),
                ],
              ),
            ),
            if (member.isAdmin) _BadgeChip(label: l10n.admin),
            if (!isAdminView && isCurrentUser) ...[
              if (member.isAdmin) const SizedBox(width: 8),
              _BadgeChip(label: l10n.you, isMuted: true),
            ],
            if (member.isPending) ...[
              if (member.isAdmin || (!isAdminView && isCurrentUser))
                const SizedBox(width: 8),
              _BadgeChip(label: l10n.pending, isMuted: true),
            ],
            if (canTap) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: colorScheme.contentLighter,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.label, this.isMuted = false});

  final String label;
  final bool isMuted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isMuted ? colorScheme.fillMuted : colorScheme.greenBase,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: textTheme.tinyBold.copyWith(
          color: isMuted ? colorScheme.textMuted : Colors.white,
        ),
      ),
    );
  }
}

class _ActionGroup extends StatelessWidget {
  const _ActionGroup({required this.children});

  final List<_ActionTile> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.fill,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          for (final entry in children.indexed) ...[
            entry.$2,
            if (entry.$1 != children.length - 1)
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: colorScheme.fillMuted,
              ),
          ],
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.isDestructive = false,
    this.trailingChevron = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool isDestructive;
  final bool trailingChevron;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final foregroundColor = isDestructive
        ? colorScheme.redBase
        : colorScheme.content;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 20, color: foregroundColor),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.body.copyWith(color: foregroundColor),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: textTheme.smallMuted),
                    ],
                  ],
                ),
              ),
              if (trailingChevron)
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: colorScheme.contentLighter,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthlyPrice {
  const _MonthlyPrice(this.displayPrice, this.value);

  final String displayPrice;
  final double value;
}

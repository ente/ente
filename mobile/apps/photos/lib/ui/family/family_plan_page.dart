import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_contacts/contacts.dart' as contacts;
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/events/contacts_changed_event.dart';
import 'package:photos/events/people_changed_event.dart';
import 'package:photos/gateways/billing/models/billing_plan.dart';
import 'package:photos/gateways/billing/models/subscription.dart';
import 'package:photos/generated/l10n.dart';
import 'package:photos/models/user_details.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/family_service.dart';
import 'package:photos/services/machine_learning/face_ml/person/person_service.dart';
import 'package:photos/services/photos_contacts_service.dart';
import 'package:photos/theme/ente_theme.dart';
import 'package:photos/theme/text_style.dart';
import 'package:photos/ui/components/buttons/button_widget_v2.dart';
import 'package:photos/ui/family/edit_storage_limit_page.dart';
import 'package:photos/ui/family/family_dashboard.dart';
import 'package:photos/ui/family/family_ui.dart';
import 'package:photos/ui/family/invite_members_page.dart';
import 'package:photos/ui/notification/toast.dart';
import 'package:photos/ui/payment/subscription.dart';
import 'package:photos/ui/viewer/search/result/edit_contact_page.dart';
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
  final Map<int, contacts.ContactRecord?> _contactsByUserId = {};
  final Map<int, Uint8List?> _profilePictureBytesByUserId = {};
  String? _startingPrice;
  bool _isRefreshing = false;
  int _memberContactsLoadGeneration = 0;
  StreamSubscription<ContactsChangedEvent>? _contactsChangedSubscription;
  StreamSubscription<PeopleChangedEvent>? _peopleChangedSubscription;

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
    unawaited(_loadMemberContacts());
    _contactsChangedSubscription = Bus.instance
        .on<ContactsChangedEvent>()
        .listen(_onContactsChanged);
    _peopleChangedSubscription = Bus.instance.on<PeopleChangedEvent>().listen((
      _,
    ) {
      if (mounted && _showsDashboard) {
        setState(() {});
      }
    });
    if (_isFreeUser && !_userDetails.isPartOfFamily()) {
      unawaited(_loadStartingPrice());
    }
  }

  @override
  void dispose() {
    _contactsChangedSubscription?.cancel();
    _peopleChangedSubscription?.cancel();
    super.dispose();
  }

  void _onContactsChanged(ContactsChangedEvent event) {
    if (!mounted || !_showsDashboard) {
      return;
    }
    if (!_familyMemberUserIDs().any(event.matchesContactUserId)) {
      return;
    }
    unawaited(_loadMemberContacts());
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
      actions: _showsDashboard ? [_buildDashboardOverflow(context)] : const [],
      scrollable: _showsDashboard,
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
    final members = _userDetails.familyData?.members ?? const <FamilyMember>[];
    final linkedPersons = _linkedPersonsFor(members);
    return FamilyDashboard(
      userDetails: _userDetails,
      members: members,
      isAdmin: isAdminView,
      contactsByUserId: _contactsByUserId,
      profilePictureBytesByUserId: _profilePictureBytesByUserId,
      linkedPersonIdsByUserId: linkedPersons.idsByUserId,
      linkedPersonNamesByUserId: linkedPersons.namesByUserId,
      onMemberTap: _showMemberActions,
      onAddMember: () => unawaited(_openInvitePage()),
      remainingSlots: _remainingSlots,
    );
  }

  ({Map<int, String> idsByUserId, Map<int, String> namesByUserId})
  _linkedPersonsFor(List<FamilyMember> members) {
    if (!PersonService.isInitialized) {
      return (idsByUserId: const {}, namesByUserId: const {});
    }
    final idsByUserId = <int, String>{};
    final namesByUserId = <int, String>{};
    for (final member in members) {
      final userID = member.userID;
      if (userID == null) {
        continue;
      }
      final personData = PersonService.instance.getCachedPartialPersonData(
        userID: userID,
        email: member.email,
      );
      final personID = personData?[PersonService.kPersonIDKey];
      if (personID == null) {
        continue;
      }
      idsByUserId[userID] = personID;
      final personName = personData?[PersonService.kNameKey]?.trim();
      if (personName != null && personName.isNotEmpty) {
        namesByUserId[userID] = personName;
      }
    }
    return (idsByUserId: idsByUserId, namesByUserId: namesByUserId);
  }

  Widget _buildDashboardOverflow(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final action = _isFamilyAdmin
        ? _FamilyDashboardOverflowAction.closePlan
        : _FamilyDashboardOverflowAction.leavePlan;
    final label = _isFamilyAdmin ? l10n.closeFamilyPlan : l10n.leaveFamilyPlan;

    return EntePopupMenuButton<_FamilyDashboardOverflowAction>(
      optionsBuilder: () async => [
        EntePopupMenuOption(
          value: action,
          label: label,
          labelColor: context.componentColors.warning,
          showDivider: false,
        ),
      ],
      onSelected: (selected) async {
        switch (selected) {
          case _FamilyDashboardOverflowAction.closePlan:
            await _confirmCloseFamily();
            break;
          case _FamilyDashboardOverflowAction.leavePlan:
            await _confirmLeaveFamily();
            break;
        }
      },
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
      unawaited(_loadMemberContacts());
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
      showToast(
        context,
        AppLocalizations.of(context).invitesSentCount(count: result!.sentCount),
      );
    }
  }

  Future<void> _showMemberActions(
    FamilyMember member,
    String fallbackDisplayName,
  ) async {
    final isCurrentUser =
        member.email.trim().toLowerCase() ==
        _userDetails.email.trim().toLowerCase();
    final savedContact = await _resolveMemberContact(member);
    if (!mounted) {
      return;
    }
    final actions = familyMemberActions(
      isAdmin: _isFamilyAdmin,
      isCurrentUser: isCurrentUser,
      member: member,
      hasSavedContact: savedContact != null,
    );
    if (actions.isEmpty) {
      return;
    }

    final savedContactName = savedContact?.data?.name.trim();
    final displayName = savedContactName == null || savedContactName.isEmpty
        ? fallbackDisplayName
        : savedContactName;
    final linkedPersonId = member.userID == null || !PersonService.isInitialized
        ? null
        : PersonService.instance.getCachedPartialPersonData(
            userID: member.userID,
            email: member.email,
          )?[PersonService.kPersonIDKey];
    final l10n = AppLocalizations.of(context);
    await showBottomSheetComponent<void>(
      context: context,
      builder: (sheetContext) => BottomSheetComponent(
        title: displayName,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < actions.length; index++) ...[
              _buildMemberActionItem(
                sheetContext,
                member: member,
                displayName: displayName,
                linkedPersonId: linkedPersonId,
                action: actions[index],
                l10n: l10n,
              ),
              if (index < actions.length - 1)
                const SizedBox(height: Spacing.sm),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMemberActionItem(
    BuildContext sheetContext, {
    required FamilyMember member,
    required String displayName,
    required String? linkedPersonId,
    required FamilyMemberAction action,
    required AppLocalizations l10n,
  }) {
    final actionLabel = switch (action) {
      FamilyMemberAction.saveContact => l10n.saveContact,
      FamilyMemberAction.editContact => l10n.editContact,
      FamilyMemberAction.editStorageLimit => l10n.editStorageLimit,
      FamilyMemberAction.removeMember => l10n.removeFromFamily,
      FamilyMemberAction.resendInvite => l10n.resendInvite,
      FamilyMemberAction.revokeInvite => l10n.revokeInvite,
    };
    final icon = switch (action) {
      FamilyMemberAction.saveContact => HugeIcons.strokeRoundedUserAdd01,
      FamilyMemberAction.editContact => HugeIcons.strokeRoundedEdit03,
      FamilyMemberAction.editStorageLimit =>
        HugeIcons.strokeRoundedFilterHorizontal,
      FamilyMemberAction.removeMember => HugeIcons.strokeRoundedUserRemove01,
      FamilyMemberAction.resendInvite => HugeIcons.strokeRoundedRefresh,
      FamilyMemberAction.revokeInvite => HugeIcons.strokeRoundedUserRemove01,
    };
    final isDestructive =
        action == FamilyMemberAction.removeMember ||
        action == FamilyMemberAction.revokeInvite;
    final subtitle = action == FamilyMemberAction.editStorageLimit
        ? member.storageLimit == null
              ? l10n.noLimitSet
              : convertBytesToReadableFormat(member.storageLimit!)
        : null;

    return MenuComponent(
      title: actionLabel,
      subtitle: subtitle,
      titleColor: isDestructive ? context.componentColors.warning : null,
      iconColor: isDestructive ? context.componentColors.warning : null,
      leading: HugeIcon(icon: icon, size: IconSizes.small, strokeWidth: 1.6),
      trailing: const Icon(Icons.chevron_right_rounded, size: IconSizes.medium),
      onTap: () async {
        Navigator.of(sheetContext).pop();
        switch (action) {
          case FamilyMemberAction.saveContact:
          case FamilyMemberAction.editContact:
            await _openMemberContact(member);
            break;
          case FamilyMemberAction.editStorageLimit:
            final updatedUserDetails = await routeToPage<UserDetails>(
              context,
              EditStorageLimitPage(
                member: member,
                displayName: displayName,
                linkedPersonId: linkedPersonId,
                totalStorageInBytes: _userDetails.getTotalStorage(),
              ),
            );
            if (!mounted) {
              return;
            }
            if (updatedUserDetails != null) {
              setState(() => _userDetails = updatedUserDetails);
              unawaited(_loadMemberContacts());
            } else {
              await _refreshUserDetails();
            }
            break;
          case FamilyMemberAction.removeMember:
            await _confirmRemoveMember(member);
            break;
          case FamilyMemberAction.resendInvite:
            await _resendInvite(member);
            break;
          case FamilyMemberAction.revokeInvite:
            await _confirmRevokeInvite(member);
            break;
        }
      },
    );
  }

  Future<contacts.ContactRecord?> _resolveMemberContact(
    FamilyMember member,
  ) async {
    final userID = member.userID;
    if (userID == null) {
      return null;
    }
    if (_contactsByUserId.containsKey(userID)) {
      return _contactsByUserId[userID];
    }

    final resolved = await _loadMemberContact(userID);
    if (!mounted) {
      return resolved.contact;
    }
    setState(() {
      _contactsByUserId[userID] = resolved.contact;
      _profilePictureBytesByUserId[userID] = resolved.profilePictureBytes;
    });
    return resolved.contact;
  }

  Future<void> _openMemberContact(FamilyMember member) async {
    final userID = member.userID;
    if (userID == null) {
      return;
    }
    final existingContact = await _resolveMemberContact(member);
    if (!mounted) {
      return;
    }

    final updatedContact = await routeToPage<contacts.ContactRecord>(
      context,
      EditContactPage(
        contactUserId: userID,
        email: member.email,
        existingContact: existingContact,
      ),
    );
    if (updatedContact == null || !mounted) {
      return;
    }

    final profilePicture = await PhotosContactsService.instance
        .getProfilePictureBytesByUserId(userID);
    if (!mounted) {
      return;
    }
    setState(() {
      _contactsByUserId[userID] = updatedContact;
      _profilePictureBytesByUserId[userID] = profilePicture;
    });
  }

  Future<void> _loadMemberContacts() async {
    final generation = ++_memberContactsLoadGeneration;
    final userIDs = _familyMemberUserIDs();
    final resolvedContacts = await Future.wait(userIDs.map(_loadMemberContact));
    if (!mounted || generation != _memberContactsLoadGeneration) {
      return;
    }
    setState(() {
      _contactsByUserId.removeWhere((userID, _) => !userIDs.contains(userID));
      _profilePictureBytesByUserId.removeWhere(
        (userID, _) => !userIDs.contains(userID),
      );
      for (final resolved in resolvedContacts) {
        _contactsByUserId[resolved.userID] = resolved.contact;
        _profilePictureBytesByUserId[resolved.userID] =
            resolved.profilePictureBytes;
      }
    });
  }

  Set<int> _familyMemberUserIDs() =>
      _userDetails.familyData?.members
          ?.map((member) => member.userID)
          .whereType<int>()
          .toSet() ??
      const <int>{};

  Future<_ResolvedMemberContact> _loadMemberContact(int userID) async {
    final contact = await PhotosContactsService.instance.getContact(
      contactUserId: userID,
    );
    final profilePicture = contact == null
        ? null
        : await PhotosContactsService.instance.getProfilePictureBytesByUserId(
            userID,
          );
    return _ResolvedMemberContact(userID, contact, profilePicture);
  }

  Future<void> _resendInvite(FamilyMember member) async {
    try {
      await FamilyService.instance.resendInvite(member);
      await _refreshUserDetails();
      if (mounted) {
        showToast(context, AppLocalizations.of(context).inviteResent);
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

enum _FamilyDashboardOverflowAction { closePlan, leavePlan }

class _ResolvedMemberContact {
  const _ResolvedMemberContact(
    this.userID,
    this.contact,
    this.profilePictureBytes,
  );

  final int userID;
  final contacts.ContactRecord? contact;
  final Uint8List? profilePictureBytes;
}

class _MonthlyPrice {
  const _MonthlyPrice(this.displayPrice, this.value);

  final String displayPrice;
  final double value;
}

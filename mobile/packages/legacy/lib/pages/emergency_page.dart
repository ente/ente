import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_configuration/base_configuration.dart";
import "package:ente_contacts/contacts.dart";
import "package:ente_legacy/components/gradient_button.dart";
import "package:ente_legacy/components/invite_reject_bottom_sheet.dart";
import "package:ente_legacy/components/legacy_kit_icons.dart";
import "package:ente_legacy/components/trusted_contact_bottom_sheet.dart";
import "package:ente_legacy/models/emergency_models.dart";
import "package:ente_legacy/models/legacy_kit_models.dart";
import "package:ente_legacy/pages/create_legacy_kit_sheet.dart";
import "package:ente_legacy/pages/legacy_kit_intro_page.dart";
import "package:ente_legacy/pages/other_contact_page.dart";
import "package:ente_legacy/pages/select_contact_page.dart";
import "package:ente_legacy/pages/share_legacy_kit_page.dart";
import "package:ente_legacy/services/emergency_service.dart";
import "package:ente_legacy/services/legacy_kit_service.dart";
import "package:ente_sharing/extensions/user_extension.dart";
import "package:ente_sharing/user_avator_widget.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/alert_bottom_sheet.dart";
import "package:ente_ui/components/captioned_text_widget_v2.dart";
import "package:ente_ui/components/divider_widget.dart";
import "package:ente_ui/components/loading_widget.dart";
import "package:ente_ui/components/menu_item_widget_v2.dart";
import "package:ente_ui/components/menu_section_title.dart";
import "package:ente_ui/theme/colors.dart";
import "package:ente_ui/theme/ente_theme.dart";
import "package:ente_ui/utils/toast_util.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:logging/logging.dart";

final _logger = Logger("EmergencyPage");

class EmergencyPage extends StatefulWidget {
  final BaseConfiguration config;
  final LegacyKitAuthenticator? legacyKitAuthenticator;

  const EmergencyPage({
    required this.config,
    this.legacyKitAuthenticator,
    super.key,
  });

  @override
  State<EmergencyPage> createState() => _EmergencyPageState();
}

class _EmergencyPageState extends State<EmergencyPage> {
  late int currentUserID;
  EmergencyInfo? info;
  List<LegacyKit> legacyKits = [];

  @override
  void initState() {
    super.initState();
    currentUserID = widget.config.getUserID()!;
    Future.delayed(const Duration(seconds: 0), () async {
      unawaited(_fetchData());
    });
  }

  Future<void> _fetchData() async {
    try {
      final result = await EmergencyContactService.instance.getInfo();
      final kits = await _fetchLegacyKits();
      if (mounted) {
        setState(() {
          info = result;
          legacyKits = kits;
        });
      }
    } catch (e) {
      if (mounted) {
        showShortToast(context, context.strings.somethingWentWrong);
      }
    }
  }

  Future<List<LegacyKit>> _fetchLegacyKits() async {
    if (!LegacyKitService.instance.isInitialized) {
      return <LegacyKit>[];
    }
    try {
      return await LegacyKitService.instance.getKits();
    } catch (error, stackTrace) {
      _logger.warning("Failed to fetch legacy kits", error, stackTrace);
      return legacyKits;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ContactsDisplayService.instance.changes,
      builder: (context, _, _) {
        final colorScheme = getEnteColorScheme(context);
        final textTheme = getEnteTextTheme(context);
        final colors = context.componentColors;
        final List<EmergencyContact> othersTrustedContacts =
            info?.othersEmergencyContact ?? [];
        final List<EmergencyContact> trustedContacts = info?.contacts ?? [];
        final hasSecondaryLegacyContent =
            legacyKits.isNotEmpty || othersTrustedContacts.isNotEmpty;
        final hasActiveLegacyKitRecovery = legacyKits.any(
          (kit) => kit.hasActiveRecoverySession,
        );
        final showFullEmptyState =
            info != null &&
            info!.recoverSessions.isEmpty &&
            trustedContacts.isEmpty &&
            othersTrustedContacts.isEmpty &&
            legacyKits.isEmpty;

        return Scaffold(
          backgroundColor: colors.backgroundBase,
          body: AppBarComponent(
            title: context.strings.legacy,
            backgroundColor: colors.backgroundBase,
            slivers: [
              if (info != null && hasActiveLegacyKitRecovery)
                SliverPadding(
                  padding: const EdgeInsets.only(top: 20, left: 16, right: 16),
                  sliver: SliverToBoxAdapter(
                    child: _WarningBanner(
                      text: context.strings.legacyKitRecoveryWarning,
                    ),
                  ),
                ),
              if (showFullEmptyState)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _FullLegacyEmptyState(
                    onAddContact: _addTrustedContact,
                    onCreateLegacyKit: LegacyKitService.instance.isInitialized
                        ? _createLegacyKit
                        : null,
                  ),
                ),
              if (info == null)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: EnteLoadingWidget()),
                ),
              if (info != null && info!.recoverSessions.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.only(top: 20, left: 16, right: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: _WarningBanner(
                            text: context.strings.recoveryWarning,
                          ),
                        );
                      }
                      final listIndex = index - 1;
                      final RecoverySessions recoverSession =
                          info!.recoverSessions[listIndex];
                      final isLastItem =
                          listIndex == info!.recoverSessions.length - 1;
                      return Column(
                        children: [
                          MenuItemWidgetV2(
                            captionedTextWidget: CaptionedTextWidgetV2(
                              title: recoverSession
                                  .emergencyContact
                                  .resolvedDisplayName,
                              textStyle: textTheme.small.copyWith(
                                color: colorScheme.warning500,
                                fontWeight: recoverSession.status.isNotEmpty
                                    ? FontWeight.bold
                                    : null,
                              ),
                            ),
                            leadingIconSize: 24.0,
                            surfaceExecutionStates: false,
                            alwaysShowSuccessState: false,
                            leadingIconWidget: UserAvatarWidget(
                              recoverSession.emergencyContact,
                              type: AvatarType.mini,
                              currentUserID: currentUserID,
                              config: widget.config,
                            ),
                            menuItemColor: colorScheme.fillFaint,
                            trailingIcon: Icons.chevron_right,
                            trailingIconIsMuted: true,
                            onTap: () async {
                              await showRejectRecoveryDialog(recoverSession);
                            },
                            isTopBorderRadiusRemoved: listIndex > 0,
                            isBottomBorderRadiusRemoved: !isLastItem,
                            isFirstItem: listIndex == 0,
                            isLastItem: isLastItem,
                          ),
                          if (!isLastItem)
                            DividerWidget(
                              dividerType: DividerType.menu,
                              bgColor: colorScheme.fillFaint,
                            ),
                        ],
                      );
                    }, childCount: 1 + info!.recoverSessions.length),
                  ),
                ),
              if (info != null &&
                  !showFullEmptyState &&
                  LegacyKitService.instance.isInitialized &&
                  (legacyKits.isNotEmpty ||
                      trustedContacts.isNotEmpty ||
                      othersTrustedContacts.isNotEmpty))
                _buildLegacyKitsSliver(colorScheme),
              if (info != null && !showFullEmptyState)
                SliverPadding(
                  padding: const EdgeInsets.only(top: 20, left: 16, right: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      if (index == 0 &&
                          (trustedContacts.isNotEmpty ||
                              hasSecondaryLegacyContent)) {
                        return _buildSectionTitle(
                          title: context.strings.trustedContacts,
                          colorScheme: colorScheme,
                          bottom: 12,
                        );
                      } else if (index > 0 && index <= trustedContacts.length) {
                        final listIndex = index - 1;
                        final contact = trustedContacts[listIndex];
                        final rowColor = colorScheme.backdropBase;
                        return Column(
                          children: [
                            MenuItemWidgetV2(
                              captionedTextWidget: CaptionedTextWidgetV2(
                                title: contact
                                    .emergencyContact
                                    .resolvedDisplayName,
                                subTitle: _contactStatusText(context, contact),
                                subTitleInNewLine: true,
                                textStyle: TextStyles.body.copyWith(
                                  color: colorScheme.textBase,
                                ),
                                subTitleTextStyle: TextStyles.mini.copyWith(
                                  color: colorScheme.textMuted,
                                ),
                              ),
                              leadingIconSize: 32.0,
                              surfaceExecutionStates: false,
                              alwaysShowSuccessState: false,
                              leadingIconWidget: _ContactAvatarWithStatus(
                                isPending: contact.isPendingInvite(),
                                borderColor: rowColor,
                                child: UserAvatarWidget(
                                  contact.emergencyContact,
                                  type: AvatarType.small,
                                  currentUserID: currentUserID,
                                  config: widget.config,
                                ),
                              ),
                              menuItemColor: rowColor,
                              singleBorderRadius: 20,
                              trailingIcon: Icons.chevron_right,
                              trailingIconIsMuted: true,
                              onTap: () async {
                                await showRevokeOrRemoveDialog(
                                  context,
                                  contact,
                                );
                              },
                            ),
                            if (listIndex < trustedContacts.length - 1)
                              const SizedBox(height: 8),
                          ],
                        );
                      } else if (index == (1 + trustedContacts.length)) {
                        if (trustedContacts.isEmpty) {
                          if (hasSecondaryLegacyContent) {
                            return _TrustedContactsEmptyCard(
                              onAddContact: _addTrustedContact,
                            );
                          }
                          return Column(
                            children: [
                              if (legacyKits.isEmpty) ...[
                                SizedBox(
                                  height: 200,
                                  width: 200,
                                  child: Image.asset(
                                    "assets/legacy.png",
                                    width: 200,
                                    height: 200,
                                  ),
                                ),
                                Text(
                                  context.strings.legacyPageDesc2,
                                  style: textTheme.smallMuted,
                                ),
                                const SizedBox(height: 16),
                              ],
                              _buildAddTrustedContactButton(),
                              if (LegacyKitService.instance.isInitialized &&
                                  legacyKits.isEmpty) ...[
                                const SizedBox(height: 12),
                                GradientButton(
                                  text: context.strings.createLegacyKit,
                                  height: 52,
                                  textStyle: TextStyles.body,
                                  onTap: () async {
                                    await _createLegacyKit();
                                  },
                                ),
                              ],
                            ],
                          );
                        }
                        return Column(
                          children: [
                            const SizedBox(height: 12),
                            _buildAddTrustedContactButton(),
                          ],
                        );
                      }
                      return const SizedBox.shrink();
                    }, childCount: 1 + trustedContacts.length + 1),
                  ),
                ),
              if (info != null &&
                  !showFullEmptyState &&
                  info!.othersEmergencyContact.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.only(top: 0, left: 16, right: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      if (index == 0 && (othersTrustedContacts.isNotEmpty)) {
                        return Column(
                          children: [
                            const SizedBox(height: 20),
                            _buildSectionTitle(
                              title: context.strings.legacyAccounts,
                              colorScheme: colorScheme,
                            ),
                          ],
                        );
                      } else if (index > 0 &&
                          index <= othersTrustedContacts.length) {
                        final listIndex = index - 1;
                        final currentUser = othersTrustedContacts[listIndex];
                        final rowColor = colorScheme.backdropBase;
                        return Column(
                          children: [
                            MenuItemWidgetV2(
                              captionedTextWidget: CaptionedTextWidgetV2(
                                title: currentUser.user.resolvedDisplayName,
                                subTitle: _contactStatusText(
                                  context,
                                  currentUser,
                                ),
                                subTitleInNewLine: true,
                                textStyle: TextStyles.body.copyWith(
                                  color: colorScheme.textBase,
                                ),
                                subTitleTextStyle: TextStyles.mini.copyWith(
                                  color: colorScheme.textMuted,
                                ),
                              ),
                              leadingIconSize: 32.0,
                              surfaceExecutionStates: false,
                              alwaysShowSuccessState: false,
                              leadingIconWidget: _ContactAvatarWithStatus(
                                isPending: currentUser.isPendingInvite(),
                                borderColor: rowColor,
                                child: UserAvatarWidget(
                                  currentUser.user,
                                  type: AvatarType.small,
                                  currentUserID: currentUserID,
                                  config: widget.config,
                                ),
                              ),
                              menuItemColor: rowColor,
                              singleBorderRadius: 20,
                              trailingIcon: Icons.chevron_right,
                              trailingIconIsMuted: true,
                              onTap: () async {
                                if (currentUser.isPendingInvite()) {
                                  await showAcceptOrDeclineDialog(
                                    context,
                                    currentUser,
                                  );
                                } else {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (BuildContext context) {
                                        return OtherContactPage(
                                          contact: currentUser,
                                          emergencyInfo: info!,
                                          config: widget.config,
                                        );
                                      },
                                    ),
                                  );
                                  if (mounted) {
                                    unawaited(_fetchData());
                                  }
                                }
                              },
                            ),
                            if (listIndex < othersTrustedContacts.length - 1)
                              const SizedBox(height: 8),
                          ],
                        );
                      }
                      return const SizedBox.shrink();
                    }, childCount: 1 + othersTrustedContacts.length + 1),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLegacyKitsSliver(EnteColorScheme colorScheme) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(
              title: context.strings.legacyKits,
              colorScheme: colorScheme,
            ),
            if (legacyKits.isEmpty)
              _LegacyKitEmptyCard(onCreate: _createLegacyKit)
            else
              ..._buildLegacyKitRows(colorScheme),
            const SizedBox(height: 12),
            if (legacyKits.isNotEmpty && legacyKits.length < 5)
              ButtonComponent(
                label: context.strings.createAnotherKit,
                variant: ButtonComponentVariant.secondary,
                shouldSurfaceExecutionStates: false,
                onTap: _createLegacyKit,
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildLegacyKitRows(EnteColorScheme colorScheme) {
    final cardColor = colorScheme.backdropBase;
    return [
      for (var index = 0; index < legacyKits.length; index++) ...[
        MenuItemWidgetV2(
          captionedTextWidget: CaptionedTextWidgetV2(
            title: legacyKits[index].displayName,
            subTitle: legacyKits[index].hasActiveRecoverySession
                ? context.strings.legacyKitRecoveryInProgress
                : context.strings.createdOn(
                    _formatKitDate(legacyKits[index].createdAt),
                  ),
            subTitleInNewLine: true,
            textStyle: TextStyles.body.copyWith(color: colorScheme.textBase),
            subTitleTextStyle: TextStyles.mini.copyWith(
              color: colorScheme.textMuted,
            ),
          ),
          leadingIconSize: 36,
          leadingIconWidget: _LegacyKitLeadingIcon(
            showWarningBadge: legacyKits[index].hasActiveRecoverySession,
          ),
          menuItemColor: cardColor,
          singleBorderRadius: 20,
          trailingIcon: Icons.chevron_right,
          trailingIconIsMuted: true,
          surfaceExecutionStates: false,
          alwaysShowSuccessState: false,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) {
                  return ShareLegacyKitPage(
                    kit: legacyKits[index],
                    accountEmail: widget.config.getEmail() ?? "",
                    authenticator: widget.legacyKitAuthenticator,
                    onChanged: _refreshLegacyData,
                  );
                },
              ),
            );
            if (mounted) {
              unawaited(_fetchData());
            }
          },
          isFirstItem: index == 0,
          isLastItem: index == legacyKits.length - 1,
        ),
        if (index < legacyKits.length - 1) const SizedBox(height: 8),
      ],
    ];
  }

  Widget _buildAddTrustedContactButton() {
    return ButtonComponent(
      label: context.strings.addTrustedContact,
      shouldSurfaceExecutionStates: false,
      onTap: _addTrustedContact,
    );
  }

  Future<void> _addTrustedContact() async {
    final result = await showAddContactSheet(
      context,
      emergencyInfo: info!,
      config: widget.config,
    );
    if (result == true) {
      unawaited(_fetchData());
    }
  }

  Widget _buildSectionTitle({
    required String title,
    required EnteColorScheme colorScheme,
    double bottom = 8,
  }) {
    return MenuSectionTitle(
      title: title,
      padding: EdgeInsets.only(bottom: bottom),
      textStyle: TextStyles.display3.copyWith(color: colorScheme.textBase),
    );
  }

  Future<void> _createLegacyKit() async {
    final isFirstLegacyKit = legacyKits.isEmpty;
    if (legacyKits.length >= 5) {
      await showAlertBottomSheet(
        context,
        title: context.strings.legacyKits,
        message: context.strings.legacyKitMaxReached,
        assetPath: "assets/warning-blue.png",
      );
      return;
    }
    if (isFirstLegacyKit) {
      final shouldStart = await showLegacyKitIntroPage(context);
      if (!shouldStart || !mounted) {
        return;
      }
    }
    await showCreateLegacyKitPage(
      context,
      accountEmail: widget.config.getEmail() ?? "",
      isFirstLegacyKit: isFirstLegacyKit,
      authenticator: widget.legacyKitAuthenticator,
      onCreated: _onLegacyKitCreated,
      onChanged: _refreshLegacyData,
    );
  }

  void _refreshLegacyData() {
    unawaited(_fetchData());
  }

  void _onLegacyKitCreated(LegacyKit kit) {
    if (!mounted) {
      return;
    }
    setState(() {
      legacyKits = [
        kit,
        ...legacyKits.where((existingKit) => existingKit.id != kit.id),
      ];
    });
    _refreshLegacyData();
  }

  String _formatKitDate(int micros) {
    final dateTime = DateTime.fromMicrosecondsSinceEpoch(micros).toLocal();
    return DateFormat.yMMMd().format(dateTime);
  }

  String _contactStatusText(BuildContext context, EmergencyContact contact) {
    return contact.isPendingInvite()
        ? context.strings.trustedContactStatusPending
        : context.strings.trustedContactStatusAccepted;
  }

  Future<void> showRevokeOrRemoveDialog(
    BuildContext context,
    EmergencyContact contact,
  ) async {
    final result = await showTrustedContactSheet(context, contact: contact);

    if (result?.action == TrustedContactAction.revoke) {
      if (!context.mounted) {
        return;
      }
      final isPending = contact.isPendingInvite();
      final colorScheme = getEnteColorScheme(context);
      final confirmed = await showAlertBottomSheet<bool>(
        context,
        title: isPending
            ? context.strings.cancelInvite
            : context.strings.removeContact,
        message: isPending
            ? context.strings.cancelInviteDesc
            : context.strings.removeContactDesc,
        assetPath: "assets/warning-grey.png",
        buttons: [
          SizedBox(
            width: double.infinity,
            child: GradientButton(
              text: isPending
                  ? context.strings.revokeInvite
                  : context.strings.removeContact,
              backgroundColor: colorScheme.warning700,
              onTap: () => Navigator.of(context).pop(true),
            ),
          ),
        ],
      );

      if (confirmed == true) {
        await EmergencyContactService.instance.updateContact(
          contact,
          ContactState.userRevokedContact,
        );
        info?.contacts.remove(contact);
        if (mounted) {
          setState(() {});
          unawaited(_fetchData());
        }
      }
    } else if (result?.action == TrustedContactAction.updateTime) {
      final selectedDays = result!.selectedDays;
      if (selectedDays == null) return;
      try {
        final success = await EmergencyContactService.instance
            .updateRecoveryNotice(contact, selectedDays);
        if (success) {
          final updatedContact = contact.copyWith(
            recoveryNoticeInDays: selectedDays,
          );
          final index = info?.contacts.indexOf(contact);
          if (index != null && index >= 0) {
            info?.contacts[index] = updatedContact;
          }
          if (mounted) {
            setState(() {});
          }
        } else {
          if (context.mounted) {
            await showAlertBottomSheet(
              context,
              title: context.strings.cannotUpdateRecoveryTime,
              message: context.strings.cannotUpdateRecoveryTimeMessage,
              assetPath: "assets/warning-blue.png",
            );
          }
        }
      } catch (e) {
        if (context.mounted) {
          showShortToast(context, context.strings.somethingWentWrong);
        }
      }
    }
  }

  Future<void> showAcceptOrDeclineDialog(
    BuildContext context,
    EmergencyContact contact,
  ) async {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    final result = await showEmailSheet<String>(
      context,
      email: contact.user.email,
      message: context.strings.legacyInvite(contact.user.email),
      buttons: [
        GradientButton(
          text: context.strings.acceptTrustInvite,
          backgroundColor: colorScheme.primary700,
          onTap: () => Navigator.of(context).pop("accept"),
        ),
        const SizedBox(height: 20),
        Center(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop("decline"),
            child: Text(
              context.strings.declineTrustInvite,
              style: textTheme.bodyBold.copyWith(
                color: colorScheme.warning400,
                decoration: TextDecoration.underline,
                decorationColor: colorScheme.warning400,
              ),
            ),
          ),
        ),
      ],
    );

    if (result == "accept") {
      await EmergencyContactService.instance.updateContact(
        contact,
        ContactState.contactAccepted,
      );
      final updatedContact = contact.copyWith(
        state: ContactState.contactAccepted,
      );
      info?.othersEmergencyContact.remove(contact);
      info?.othersEmergencyContact.add(updatedContact);
      if (mounted) {
        setState(() {});
      }
    } else if (result == "decline") {
      await EmergencyContactService.instance.updateContact(
        contact,
        ContactState.contactDenied,
      );
      info?.othersEmergencyContact.remove(contact);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> showRejectRecoveryDialog(RecoverySessions session) async {
    final String emergencyContactEmail = session.emergencyContact.email;
    final colorScheme = getEnteColorScheme(context);

    final confirmed = await showEmailSheet<bool>(
      context,
      email: emergencyContactEmail,
      message: context.strings.recoveryWarningBody(emergencyContactEmail),
      buttons: [
        GradientButton(
          text: context.strings.rejectRecovery,
          backgroundColor: colorScheme.warning700,
          onTap: () => Navigator.of(context).pop(true),
        ),
        if (kDebugMode) ...[
          const SizedBox(height: 8),
          GradientButton(
            text: "Approve recovery (to be removed)",
            backgroundColor: colorScheme.primary700,
            onTap: () async {
              Navigator.of(context).pop();
              await EmergencyContactService.instance.approveRecovery(session);
              if (mounted) {
                setState(() {});
              }
              unawaited(_fetchData());
            },
          ),
        ],
      ],
    );

    if (confirmed == true) {
      await EmergencyContactService.instance.rejectRecovery(session);
      info?.recoverSessions.removeWhere((element) => element.id == session.id);
      if (mounted) {
        setState(() {});
      }
      unawaited(_fetchData());
    }
  }
}

class _ContactAvatarWithStatus extends StatelessWidget {
  final Widget child;
  final bool isPending;
  final Color borderColor;

  const _ContactAvatarWithStatus({
    required this.child,
    required this.isPending,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (isPending)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: colorScheme.caution500,
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: 1.5),
              ),
              child: const Center(
                child: Text(
                  "!",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 7.0,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FullLegacyEmptyState extends StatelessWidget {
  final Future<void> Function() onAddContact;
  final Future<void> Function()? onCreateLegacyKit;

  const _FullLegacyEmptyState({
    required this.onAddContact,
    required this.onCreateLegacyKit,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  "assets/legacy.png",
                  width: 234,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 24),
                Text(
                  context.strings.legacyEmptyStateDescription,
                  textAlign: TextAlign.center,
                  style: TextStyles.body.copyWith(color: colorScheme.textMuted),
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(16, 0, 16, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ButtonComponent(
                label: context.strings.addTrustedContact,
                variant: ButtonComponentVariant.secondary,
                shouldSurfaceExecutionStates: false,
                onTap: onAddContact,
              ),
              if (onCreateLegacyKit != null) ...[
                const SizedBox(height: 12),
                ButtonComponent(
                  label: context.strings.createLegacyKit,
                  shouldSurfaceExecutionStates: false,
                  onTap: onCreateLegacyKit,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _LegacyKitLeadingIcon extends StatelessWidget {
  final bool showWarningBadge;

  const _LegacyKitLeadingIcon({required this.showWarningBadge});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);

    return SizedBox.square(
      dimension: 36,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(child: LegacyKitRowIcon(color: colorScheme.primary700)),
          if (showWarningBadge)
            const Positioned(
              left: 20,
              top: 20,
              child: SizedBox.square(
                dimension: 18,
                child: Center(child: LegacyKitAlertIcon()),
              ),
            ),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final String text;

  const _WarningBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final backgroundColor = colorScheme.isLightTheme
        ? const Color(0xFFFAEBEB)
        : const Color(0xFF292929);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(
            width: 18,
            height: 20,
            child: Center(child: LegacyKitAlertIcon()),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: textTheme.bodyBold.copyWith(color: colorScheme.warning400),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustedContactsEmptyCard extends StatelessWidget {
  final Future<void> Function() onAddContact;

  const _TrustedContactsEmptyCard({required this.onAddContact});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final cardColor = colorScheme.isLightTheme
        ? Colors.white
        : colorScheme.backdropBase;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            colorScheme.isLightTheme
                ? "assets/trusted_contact_empty.png"
                : "assets/trusted_contact_empty_dark.png",
            width: 45,
            height: 45,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 12),
          Text(
            context.strings.trustedContactsEmptyDescription,
            textAlign: TextAlign.center,
            style: TextStyles.body.copyWith(color: colorScheme.textMuted),
          ),
          const SizedBox(height: 12),
          GradientButton(
            text: context.strings.addTrustedContact,
            height: 52,
            textStyle: TextStyles.body,
            onTap: () async {
              await onAddContact();
            },
          ),
        ],
      ),
    );
  }
}

class _LegacyKitEmptyCard extends StatelessWidget {
  final Future<void> Function() onCreate;

  const _LegacyKitEmptyCard({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final cardColor = colorScheme.isLightTheme
        ? Colors.white
        : colorScheme.backgroundElevated2;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            "assets/legacy_kit_empty.png",
            width: 43,
            height: 42,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 12),
          Text(
            context.strings.legacyKitEmptyDescription,
            textAlign: TextAlign.center,
            style: TextStyles.body.copyWith(color: colorScheme.textMuted),
          ),
          const SizedBox(height: 12),
          GradientButton(
            text: context.strings.createLegacyKit,
            height: 52,
            textStyle: TextStyles.body,
            onTap: () async {
              await onCreate();
            },
          ),
        ],
      ),
    );
  }
}

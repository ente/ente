import "dart:async";

import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:photos/core/configuration.dart";
import "package:photos/emergency/components/email_action_sheet.dart";
import "package:photos/emergency/components/trusted_contact_sheet.dart";
import "package:photos/emergency/emergency_service.dart";
import "package:photos/emergency/model.dart";
import "package:photos/emergency/other_contact_page.dart";
import "package:photos/emergency/select_contact_page.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/services/contacts/contact_identity_resolver.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/components/alert_bottom_sheet.dart";
import "package:photos/ui/components/buttons/button_widget_v2.dart";
import "package:photos/ui/components/divider_widget.dart";
import "package:photos/ui/components/menu_item_widget/menu_item_widget_new.dart";
import "package:photos/ui/components/menu_section_title.dart";
import "package:photos/ui/components/title_bar_title_widget.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/sharing/user_avator_widget.dart";

class EmergencyPage extends StatefulWidget {
  const EmergencyPage({super.key});

  @override
  State<EmergencyPage> createState() => _EmergencyPageState();
}

class _EmergencyPageState extends State<EmergencyPage> {
  late int currentUserID;
  EmergencyInfo? info;

  @override
  void initState() {
    super.initState();
    currentUserID = Configuration.instance.getUserID()!;
    Future.delayed(const Duration(seconds: 0), () async {
      unawaited(_fetchData());
    });
  }

  Future<void> _fetchData() async {
    try {
      final result = await EmergencyContactService.instance.getInfo();
      if (mounted) {
        setState(() {
          info = result;
        });
      }
    } catch (e) {
      if (!mounted) return;
      showShortToast(context, AppLocalizations.of(context).somethingWentWrong);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final l10n = context.l10n;
    final List<EmergencyContact> othersTrustedContacts =
        info?.othersEmergencyContact ?? [];
    final List<EmergencyContact> trustedContacts = info?.contacts ?? [];

    return Scaffold(
      backgroundColor: colorScheme.backgroundColour,
      appBar: AppBar(
        backgroundColor: colorScheme.backgroundColour,
        toolbarHeight: 48,
        leadingWidth: 48,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_outlined),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TitleBarTitleWidget(title: l10n.legacy),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(l10n.legacyPageDesc, style: textTheme.smallMuted),
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
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _WarningBanner(text: l10n.recoveryWarning),
                    );
                  }

                  final listIndex = index - 1;
                  final recoverSession = info!.recoverSessions[listIndex];
                  final isLastItem =
                      listIndex == info!.recoverSessions.length - 1;
                  final emergencyUser = recoverSession.emergencyContact;
                  return _buildGroupedMenuItem(
                    listIndex: listIndex,
                    isLastItem: isLastItem,
                    child: MenuItemWidgetNew(
                      title: resolveDisplayName(emergencyUser),
                      titleColor: colorScheme.warning500,
                      leadingIconSize: 24,
                      leadingIconWidget: UserAvatarWidget(
                        emergencyUser,
                        type: AvatarType.medium,
                        currentUserID: currentUserID,
                      ),
                      menuItemColor: colorScheme.fillFaint,
                      trailingWidget: _buildTrailingWidget(showWarning: false),
                      borderRadius: 0,
                      onTap: () async {
                        await showRejectRecoveryDialog(recoverSession);
                      },
                    ),
                  );
                }, childCount: 1 + info!.recoverSessions.length),
              ),
            ),
          if (info != null)
            SliverPadding(
              padding: const EdgeInsets.only(
                top: 16,
                left: 16,
                right: 16,
                bottom: 8,
              ),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  if (index == 0 && trustedContacts.isNotEmpty) {
                    return MenuSectionTitle(title: l10n.trustedContacts);
                  }

                  if (index > 0 && index <= trustedContacts.length) {
                    final listIndex = index - 1;
                    final contact = trustedContacts[listIndex];
                    final isLastItem = listIndex == trustedContacts.length - 1;
                    final emergencyUser = contact.emergencyContact;
                    return _buildGroupedMenuItem(
                      listIndex: listIndex,
                      isLastItem: isLastItem,
                      child: MenuItemWidgetNew(
                        title: resolveDisplayName(emergencyUser),
                        titleColor: contact.isPendingInvite()
                            ? colorScheme.warning500
                            : textTheme.small.color,
                        leadingIconSize: 24,
                        leadingIconWidget: UserAvatarWidget(
                          emergencyUser,
                          type: AvatarType.medium,
                          currentUserID: currentUserID,
                        ),
                        menuItemColor: colorScheme.fillFaint,
                        trailingWidget: _buildTrailingWidget(
                          showWarning: contact.isPendingInvite(),
                        ),
                        borderRadius: 0,
                        onTap: () async {
                          await showRevokeOrRemoveDialog(context, contact);
                        },
                      ),
                    );
                  }

                  if (index == (1 + trustedContacts.length)) {
                    if (trustedContacts.isEmpty) {
                      return Column(
                        children: [
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
                            l10n.legacyPageDesc2,
                            style: textTheme.smallMuted,
                          ),
                          const SizedBox(height: 16),
                          ButtonWidgetV2(
                            buttonType: ButtonTypeV2.primary,
                            labelText: l10n.addTrustedContact,
                            shouldSurfaceExecutionStates: false,
                            onTap: () async {
                              final result = await showAddContactSheet(
                                context,
                                emergencyInfo: info!,
                              );
                              if (result == true) {
                                unawaited(_fetchData());
                              }
                            },
                          ),
                        ],
                      );
                    }

                    return Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: ButtonWidgetV2(
                        buttonType: ButtonTypeV2.primary,
                        labelText: l10n.addTrustedContact,
                        shouldSurfaceExecutionStates: false,
                        onTap: () async {
                          final result = await showAddContactSheet(
                            context,
                            emergencyInfo: info!,
                          );
                          if (result == true) {
                            unawaited(_fetchData());
                          }
                        },
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                }, childCount: 1 + trustedContacts.length + 1),
              ),
            ),
          if (info != null && info!.othersEmergencyContact.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.only(top: 0, left: 16, right: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  if (index == 0 && othersTrustedContacts.isNotEmpty) {
                    return Column(
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: DividerWidget(dividerType: DividerType.solid),
                        ),
                        MenuSectionTitle(title: l10n.legacyAccounts),
                      ],
                    );
                  }

                  if (index > 0 && index <= othersTrustedContacts.length) {
                    final listIndex = index - 1;
                    final currentUser = othersTrustedContacts[listIndex];
                    final isLastItem = index == othersTrustedContacts.length;
                    final emergencyUser = currentUser.user;
                    return _buildGroupedMenuItem(
                      listIndex: listIndex,
                      isLastItem: isLastItem,
                      child: MenuItemWidgetNew(
                        title: resolveDisplayName(emergencyUser),
                        titleColor: currentUser.isPendingInvite()
                            ? colorScheme.warning500
                            : textTheme.small.color,
                        leadingIconSize: 24,
                        leadingIconWidget: UserAvatarWidget(
                          emergencyUser,
                          type: AvatarType.medium,
                          currentUserID: currentUserID,
                        ),
                        menuItemColor: colorScheme.fillFaint,
                        trailingWidget: _buildTrailingWidget(
                          showWarning: currentUser.isPendingInvite(),
                        ),
                        borderRadius: 0,
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
                    );
                  }
                  return const SizedBox.shrink();
                }, childCount: 1 + othersTrustedContacts.length + 1),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGroupedMenuItem({
    required int listIndex,
    required bool isLastItem,
    required Widget child,
  }) {
    final colorScheme = getEnteColorScheme(context);
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.vertical(
            top: listIndex == 0 ? const Radius.circular(14) : Radius.zero,
            bottom: isLastItem ? const Radius.circular(14) : Radius.zero,
          ),
          child: child,
        ),
        if (!isLastItem)
          DividerWidget(
            dividerType: DividerType.menu,
            bgColor: colorScheme.fillFaint,
          ),
      ],
    );
  }

  Widget _buildTrailingWidget({required bool showWarning}) {
    final colorScheme = getEnteColorScheme(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showWarning) ...[
          Image.asset("assets/warning-yellow.png", width: 20, height: 20),
          const SizedBox(width: 6),
        ],
        Icon(Icons.chevron_right, color: colorScheme.strokeMuted),
      ],
    );
  }

  Future<void> showRevokeOrRemoveDialog(
    BuildContext context,
    EmergencyContact contact,
  ) async {
    final actionResult = await showTrustedContactSheet(
      context,
      contact: contact,
    );
    if (actionResult == null) {
      return;
    }

    if (actionResult.action == TrustedContactAction.revoke) {
      final isPending = contact.isPendingInvite();
      if (!context.mounted) return;
      final confirmed = await showAlertBottomSheet<bool>(
        context,
        title: isPending
            ? context.l10n.cancelInvite
            : context.l10n.removeContact,
        assetPath: "assets/warning-grey.png",
        message: isPending
            ? context.l10n.cancelInviteDesc
            : context.l10n.removeContactDesc,
        buttons: [
          ButtonWidgetV2(
            buttonType: ButtonTypeV2.critical,
            labelText: isPending
                ? context.l10n.revokeInvite
                : context.l10n.removeContact,
            onTap: () async => Navigator.of(context).pop(true),
            shouldSurfaceExecutionStates: false,
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
      return;
    }

    final selectedDays = actionResult.selectedDays;
    if (actionResult.action != TrustedContactAction.updateTime ||
        selectedDays == null) {
      return;
    }

    try {
      final success = await EmergencyContactService.instance
          .updateRecoveryNotice(contact, selectedDays);
      if (success) {
        final updatedContact = contact.copyWith(
          recoveryNoticeInDays: selectedDays,
        );
        final index = info?.contacts.indexWhere(
          (element) =>
              element.user.id == contact.user.id &&
              element.emergencyContact.id == contact.emergencyContact.id,
        );
        if (index != null && index >= 0) {
          info?.contacts[index] = updatedContact;
        }
        if (mounted) {
          setState(() {});
        }
      } else {
        if (mounted) {
          if (!context.mounted) return;
          await showAlertBottomSheet(
            context,
            title: context.l10n.cannotUpdateRecoveryTime,
            message: context.l10n.cannotUpdateRecoveryTimeMessage,
            assetPath: "assets/warning-grey.png",
          );
        }
      }
    } catch (e) {
      if (mounted) {
        if (!context.mounted) return;
        showShortToast(
          context,
          AppLocalizations.of(context).somethingWentWrong,
        );
      }
    }
  }

  Future<void> showAcceptOrDeclineDialog(
    BuildContext context,
    EmergencyContact contact,
  ) async {
    final result = await showEmailActionSheet<String>(
      context,
      email: contact.user.email,
      message: AppLocalizations.of(
        context,
      ).legacyInvite(email: contact.user.email),
      buttons: [
        ButtonWidgetV2(
          buttonType: ButtonTypeV2.primary,
          labelText: AppLocalizations.of(context).acceptTrustInvite,
          shouldSurfaceExecutionStates: false,
          onTap: () async => Navigator.of(context).pop("accept"),
        ),
        ButtonWidgetV2(
          buttonType: ButtonTypeV2.tertiaryCritical,
          labelText: AppLocalizations.of(context).declineTrustInvite,
          shouldSurfaceExecutionStates: false,
          onTap: () async => Navigator.of(context).pop("decline"),
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
      return;
    }

    if (result == "decline") {
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
    final emergencyContactEmail = session.emergencyContact.email;

    final confirmed = await showEmailActionSheet<bool>(
      context,
      email: emergencyContactEmail,
      message: context.l10n.recoveryWarningBody(email: emergencyContactEmail),
      buttons: [
        ButtonWidgetV2(
          buttonType: ButtonTypeV2.critical,
          labelText: context.l10n.rejectRecovery,
          shouldSurfaceExecutionStates: false,
          onTap: () async => Navigator.of(context).pop(true),
        ),
        if (kDebugMode)
          ButtonWidgetV2(
            buttonType: ButtonTypeV2.secondary,
            labelText: "Approve recovery (to be removed)",
            shouldSurfaceExecutionStates: false,
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

class _WarningBanner extends StatelessWidget {
  final String text;

  const _WarningBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.warning400.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Image.asset("assets/emergency-warning.png", width: 32, height: 32),
          const SizedBox(width: 12),
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

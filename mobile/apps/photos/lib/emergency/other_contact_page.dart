import "package:collection/collection.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/emergency/emergency_service.dart";
import "package:photos/emergency/model.dart";
import "package:photos/emergency/recover_others_account.dart";
import "package:photos/gateways/users/models/key_attributes.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/alert_bottom_sheet.dart";
import "package:photos/ui/components/buttons/button_widget_v2.dart";
import "package:photos/ui/components/title_bar_title_widget.dart";
import "package:photos/utils/dialog_util.dart";

class OtherContactPage extends StatefulWidget {
  final EmergencyContact contact;
  final EmergencyInfo emergencyInfo;

  const OtherContactPage({
    required this.contact,
    required this.emergencyInfo,
    super.key,
  });

  @override
  State<OtherContactPage> createState() => _OtherContactPageState();
}

class _OtherContactPageState extends State<OtherContactPage> {
  late String accountEmail = widget.contact.user.email;
  RecoverySessions? recoverySession;
  String? waitTill;
  final Logger _logger = Logger("_OtherContactPageState");
  late EmergencyInfo emergencyInfo = widget.emergencyInfo;

  @override
  void initState() {
    super.initState();
    recoverySession = widget.emergencyInfo.othersRecoverySession
        .firstWhereOrNull((session) => session.user.email == accountEmail);
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final result = await EmergencyContactService.instance.getInfo();
      if (mounted) {
        setState(() {
          recoverySession = result.othersRecoverySession.firstWhereOrNull(
            (session) => session.user.email == accountEmail,
          );
        });
      }
    } catch (e) {
      _logger.severe("Error fetching data", e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (recoverySession != null) {
      final dateTime = DateTime.now().add(
        Duration(microseconds: recoverySession!.waitTill),
      );
      waitTill = getFormattedTime(dateTime, context: context);
    }
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        leadingWidth: 48,
        backgroundColor: colorScheme.backgroundColour,
        leading: GestureDetector(
          onTap: () {
            Navigator.pop(context);
          },
          child: const Icon(Icons.arrow_back_outlined),
        ),
      ),
      backgroundColor: colorScheme.backgroundColour,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TitleBarTitleWidget(title: context.strings.recoverAccount),
            Text(accountEmail, style: textTheme.smallMuted),
            const SizedBox(height: 12),
            if (recoverySession == null)
              Text(
                context.strings.recoverAccountDesc(
                  email: accountEmail,
                  days: widget.contact.recoveryNoticeInDays,
                ),
                style: textTheme.smallMuted,
              ),
            if (recoverySession != null && recoverySession!.status == "READY")
              Text(
                context.strings.recoveryReady(email: accountEmail),
                style: textTheme.smallMuted,
              ),
            if (recoverySession != null && recoverySession!.status == "WAITING")
              Text(
                context.strings.recoverAccountAfter(
                  email: accountEmail,
                  time: waitTill!,
                ),
                style: textTheme.smallMuted,
              ),
            const SizedBox(height: 24),
            if (recoverySession == null)
              ButtonWidgetV2(
                buttonType: ButtonTypeV2.primary,
                labelText: context.strings.startRecovery,
                isDisabled: widget.contact.isPendingInvite(),
                shouldSurfaceExecutionStates: false,
                onTap: widget.contact.isPendingInvite()
                    ? null
                    : () async {
                        final confirmed = await showAlertBottomSheet<bool>(
                          context,
                          title: context.strings.startRecovery,
                          message: context.strings.startRecoveryDesc(
                            email: accountEmail,
                          ),
                          assetPath: "assets/warning-grey.png",
                          buttons: [
                            ButtonWidgetV2(
                              buttonType: ButtonTypeV2.primary,
                              labelText: context.strings.startRecovery,
                              onTap: () async =>
                                  Navigator.of(context).pop(true),
                              shouldSurfaceExecutionStates: false,
                            ),
                          ],
                        );
                        if (confirmed != true) {
                          return;
                        }
                        try {
                          await EmergencyContactService.instance.startRecovery(
                            widget.contact,
                          );
                          if (mounted) {
                            _fetchData().ignore();
                            if (!context.mounted) return;
                            await showAlertBottomSheet(
                              context,
                              title: context.strings.recoveryInitiated,
                              message: context.strings.recoveryInitiatedDesc(
                                days: widget.contact.recoveryNoticeInDays,
                                email: Configuration.instance.getEmail()!,
                              ),
                              assetPath: "assets/warning-grey.png",
                            );
                          }
                        } catch (e) {
                          if (!context.mounted) return;
                          showGenericErrorBottomSheet(
                            context: context,
                            error: e,
                          ).ignore();
                        }
                      },
              ),
            if (recoverySession != null && recoverySession!.status == "READY")
              ButtonWidgetV2(
                buttonType: ButtonTypeV2.primary,
                labelText: context.strings.recoverAccount,
                shouldSurfaceExecutionStates: false,
                onTap: () async {
                  try {
                    final (
                      String key,
                      KeyAttributes attributes,
                    ) = await EmergencyContactService.instance.getRecoveryInfo(
                      recoverySession!,
                    );
                    routeToPage(
                      context,
                      RecoverOthersAccount(key, attributes, recoverySession!),
                    ).ignore();
                  } catch (e) {
                    showGenericErrorBottomSheet(
                      context: context,
                      error: e,
                    ).ignore();
                  }
                },
              ),
            if (recoverySession != null && recoverySession!.status == "WAITING")
              ButtonWidgetV2(
                buttonType: ButtonTypeV2.secondary,
                labelText: context.strings.cancelRecovery,
                shouldSurfaceExecutionStates: false,
                onTap: () async {
                  await _showCancelRecoverySheet();
                },
              ),
            if (recoverySession != null &&
                recoverySession!.status == "READY") ...[
              const SizedBox(height: 20),
              ButtonWidgetV2(
                buttonType: ButtonTypeV2.tertiaryCritical,
                labelText: context.strings.cancelRecovery,
                shouldSurfaceExecutionStates: false,
                onTap: () async {
                  await _showCancelRecoverySheet();
                },
              ),
              const SizedBox(height: 24),
              Text(
                context.strings.orRemoveYourself(email: accountEmail),
                style: textTheme.smallMuted,
              ),
              const SizedBox(height: 12),
              ButtonWidgetV2(
                buttonType: ButtonTypeV2.tertiaryCritical,
                labelText: context.strings.removeContact,
                shouldSurfaceExecutionStates: false,
                onTap: showRemoveSheet,
              ),
            ],
            if (recoverySession == null ||
                recoverySession!.status != "READY") ...[
              const SizedBox(height: 20),
              ButtonWidgetV2(
                buttonType: ButtonTypeV2.tertiaryCritical,
                labelText: context.strings.removeContact,
                shouldSurfaceExecutionStates: false,
                onTap: showRemoveSheet,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showCancelRecoverySheet() async {
    final confirmed = await showAlertBottomSheet<bool>(
      context,
      title: context.strings.cancelRecovery,
      message: context.strings.cancelRecoveryDesc(email: accountEmail),
      assetPath: "assets/warning-grey.png",
      buttons: [
        ButtonWidgetV2(
          buttonType: ButtonTypeV2.critical,
          labelText: context.strings.cancelRecovery,
          onTap: () async => Navigator.of(context).pop(true),
          shouldSurfaceExecutionStates: false,
        ),
      ],
    );
    if (confirmed == true) {
      try {
        await EmergencyContactService.instance.stopRecovery(recoverySession!);
        if (mounted) {
          _fetchData().ignore();
        }
      } catch (e) {
        if (!mounted) return;
        showGenericErrorBottomSheet(context: context, error: e).ignore();
      }
    }
  }

  Future<void> showRemoveSheet() async {
    final confirmed = await showAlertBottomSheet<bool>(
      context,
      title: context.strings.removeContact,
      message: context.strings.removeYourselfDesc(email: accountEmail),
      assetPath: "assets/warning-grey.png",
      buttons: [
        ButtonWidgetV2(
          buttonType: ButtonTypeV2.critical,
          labelText: context.strings.removeContact,
          onTap: () async => Navigator.of(context).pop(true),
          shouldSurfaceExecutionStates: false,
        ),
      ],
    );
    if (confirmed == true) {
      try {
        await EmergencyContactService.instance.updateContact(
          widget.contact,
          ContactState.contactLeft,
        );
        if (mounted) {
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (!mounted) return;
        showGenericErrorBottomSheet(context: context, error: e).ignore();
      }
    }
  }
}

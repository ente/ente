import "dart:async";

import "package:collection/collection.dart";
import "package:ente_base/models/key_attributes.dart";
import "package:ente_configuration/base_configuration.dart";
import "package:ente_legacy/components/gradient_button.dart";
import "package:ente_legacy/models/emergency_models.dart";
import "package:ente_legacy/pages/recover_others_account.dart";
import "package:ente_legacy/services/emergency_service.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/alert_bottom_sheet.dart";
import "package:ente_ui/components/title_bar_title_widget.dart";
import "package:ente_ui/theme/ente_theme.dart";
import "package:ente_ui/utils/dialog_util.dart";
import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:logging/logging.dart";

// OtherContactPage is used to start recovery process for other user's account
// Based on the state of the contact & recovery session, it will show
// different UI
class OtherContactPage extends StatefulWidget {
  final EmergencyContact contact;
  final EmergencyInfo emergencyInfo;
  final BaseConfiguration config;

  const OtherContactPage({
    required this.contact,
    required this.emergencyInfo,
    required this.config,
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
    _logger.info('session ${widget.emergencyInfo}');
    if (recoverySession != null) {
      final dateTime = DateTime.now().add(
        Duration(microseconds: recoverySession!.waitTill),
      );
      waitTill = _getFormattedTime(context, dateTime);
    }
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        leadingWidth: 48,
        leading: GestureDetector(
          onTap: () {
            Navigator.pop(context);
          },
          child: const Icon(Icons.arrow_back_outlined),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TitleBarTitleWidget(title: context.strings.recoverAccount),
            Text(accountEmail, style: textTheme.smallMuted),
            const SizedBox(height: 12),
            // Description text based on recovery state
            if (recoverySession == null)
              Text(
                context.strings.recoverAccountDesc(
                  accountEmail,
                  widget.contact.recoveryNoticeInDays,
                ),
                style: textTheme.smallMuted,
              ),
            if (recoverySession != null && recoverySession!.status == "READY")
              Text(
                context.strings.recoveryReady(accountEmail),
                style: textTheme.smallMuted,
              ),
            if (recoverySession != null && recoverySession!.status == "WAITING")
              Text(
                context.strings.recoverAccountAfter(accountEmail, waitTill!),
                style: textTheme.smallMuted,
              ),
            const SizedBox(height: 24),
            // Start recovery button (no active session)
            if (recoverySession == null)
              GradientButton(
                text: context.strings.startRecovery,
                backgroundColor: colorScheme.primary700,
                onTap: widget.contact.isPendingInvite()
                    ? () {}
                    : () async {
                        final confirmed = await showAlertBottomSheet<bool>(
                          context,
                          title: context.strings.startRecovery,
                          message: context.strings.startRecoveryDesc(
                            accountEmail,
                          ),
                          assetPath: "assets/warning-grey.png",
                          buttons: [
                            SizedBox(
                              width: double.infinity,
                              child: GradientButton(
                                text: context.strings.startRecovery,
                                backgroundColor: colorScheme.primary700,
                                onTap: () => Navigator.of(context).pop(true),
                              ),
                            ),
                          ],
                        );

                        if (confirmed == true) {
                          try {
                            await EmergencyContactService.instance
                                .startRecovery(widget.contact);
                            if (context.mounted) {
                              _fetchData().ignore();
                              await showAlertBottomSheet(
                                context,
                                title: context.strings.recoveryInitiated,
                                message: context.strings.recoveryInitiatedDesc(
                                  widget.contact.recoveryNoticeInDays,
                                  widget.config.getEmail()!,
                                ),
                                assetPath: "assets/warning-grey.png",
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              showGenericErrorDialog(
                                context: context,
                                error: e,
                              ).ignore();
                            }
                          }
                        }
                      },
              ),
            if (recoverySession != null && recoverySession!.status == "READY")
              GradientButton(
                text: context.strings.recoverAccount,
                backgroundColor: colorScheme.primary700,
                onTap: () async {
                  try {
                    final (
                      String key,
                      KeyAttributes attributes,
                    ) = await EmergencyContactService.instance.getRecoveryInfo(
                      recoverySession!,
                    );
                    if (!context.mounted) {
                      return;
                    }
                    routeToPage(
                      context,
                      RecoverOthersAccount(key, attributes, recoverySession!),
                    ).ignore();
                  } catch (e) {
                    if (context.mounted) {
                      showGenericErrorDialog(
                        context: context,
                        error: e,
                      ).ignore();
                    }
                  }
                },
              ),
            if (recoverySession != null && recoverySession!.status == "WAITING")
              GradientButton(
                text: context.strings.cancelRecovery,
                backgroundColor: colorScheme.primary700,
                onTap: () => _showCancelRecoverySheet(),
              ),
            if (recoverySession != null &&
                recoverySession!.status == "READY") ...[
              const SizedBox(height: 20),
              Center(
                child: GestureDetector(
                  onTap: () => _showCancelRecoverySheet(),
                  child: Text(
                    context.strings.cancelRecovery,
                    style: textTheme.bodyBold.copyWith(
                      color: colorScheme.warning400,
                      decoration: TextDecoration.underline,
                      decorationColor: colorScheme.warning400,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                context.strings.orRemoveYourself(accountEmail),
                style: textTheme.smallMuted,
              ),
              const SizedBox(height: 12),
              GradientButton(
                text: context.strings.removeContact,
                backgroundColor: colorScheme.warning400,
                onTap: () async {
                  await showRemoveSheet();
                },
              ),
            ],
            if (recoverySession == null ||
                recoverySession!.status != "READY") ...[
              const SizedBox(height: 20),
              Center(
                child: GestureDetector(
                  onTap: () async {
                    await showRemoveSheet();
                  },
                  child: Text(
                    context.strings.removeContact,
                    style: textTheme.bodyBold.copyWith(
                      color: colorScheme.warning400,
                      decoration: TextDecoration.underline,
                      decorationColor: colorScheme.warning400,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getFormattedTime(BuildContext context, DateTime dateTime) {
    return DateFormat(
      'E, MMM d, y - HH:mm',
      Localizations.localeOf(context).languageCode,
    ).format(dateTime);
  }

  Future<void> _showCancelRecoverySheet() async {
    final colorScheme = getEnteColorScheme(context);
    final confirmed = await showAlertBottomSheet<bool>(
      context,
      title: context.strings.cancelRecovery,
      message: context.strings.cancelRecoveryDesc(accountEmail),
      assetPath: "assets/warning-grey.png",
      buttons: [
        SizedBox(
          width: double.infinity,
          child: GradientButton(
            text: context.strings.cancelRecovery,
            backgroundColor: colorScheme.warning700,
            onTap: () => Navigator.of(context).pop(true),
          ),
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
        if (mounted) {
          showGenericErrorDialog(context: context, error: e).ignore();
        }
      }
    }
  }

  Future<void> showRemoveSheet() async {
    final colorScheme = getEnteColorScheme(context);
    final confirmed = await showAlertBottomSheet<bool>(
      context,
      title: context.strings.removeContact,
      message: context.strings.removeYourselfDesc(accountEmail),
      assetPath: "assets/warning-grey.png",
      buttons: [
        SizedBox(
          width: double.infinity,
          child: GradientButton(
            text: context.strings.removeContact,
            backgroundColor: colorScheme.warning700,
            onTap: () => Navigator.of(context).pop(true),
          ),
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
        if (mounted) {
          showGenericErrorDialog(context: context, error: e).ignore();
        }
      }
    }
  }
}

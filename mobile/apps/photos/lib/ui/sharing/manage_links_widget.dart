import 'dart:async';
import 'dart:convert';

import 'package:ente_components/ente_components.dart';
import 'package:ente_crypto/ente_crypto.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import "package:ente_strings/ente_strings.dart";
import 'package:ente_ui/components/date_time_picker.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:photos/core/constants.dart';
import "package:photos/core/errors.dart";
import "package:photos/gateways/collections/models/public_url.dart";
import 'package:photos/models/collection/collection.dart';
import 'package:photos/services/collections_service.dart';
import 'package:photos/ui/actions/collection/collection_sharing_actions.dart';
import 'package:photos/ui/components/buttons/button_widget.dart';
import 'package:photos/ui/components/dialog_widget.dart';
import 'package:photos/ui/components/models/button_type.dart';
import 'package:photos/ui/notification/toast.dart';
import 'package:photos/ui/payment/subscription.dart';
import 'package:photos/ui/sharing/pickers/layout_picker_page.dart';
import 'package:photos/ui/sharing/public_link_enabled_actions_widget.dart';
import 'package:photos/ui/sharing/share_components.dart';
import 'package:photos/utils/dialog_util.dart';
import 'package:photos/utils/public_link_layout_util.dart';

class ManageSharedLinkWidget extends StatefulWidget {
  final Collection collection;

  const ManageSharedLinkWidget({super.key, required this.collection});

  @override
  State<ManageSharedLinkWidget> createState() => _ManageSharedLinkWidgetState();
}

class _ManageSharedLinkWidgetState extends State<ManageSharedLinkWidget> {
  static const Duration _expiryPresetSelectionTolerance = Duration(minutes: 5);

  final CollectionActions sharingActions = CollectionActions(
    CollectionsService.instance,
  );
  final GlobalKey sendLinkButtonKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final collection = widget.collection;
    final url = collection.publicURLs.first;
    final isQuickLink = collection.isQuickLinkCollection();

    return ShareScaffold(
      title: context.strings.linkSettings,
      children: [
        PublicLinkEnabledActionsWidget(
          collection: collection,
          sendLinkButtonKey: sendLinkButtonKey,
          showEmbedHtml: true,
          showShareActions: isQuickLink,
        ),
        if (!url.isExpired)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.sm),
            child: Text(
              context.strings.publicLinkAccessDescription,
              style: TextStyles.mini.copyWith(
                color: context.componentColors.textLight,
              ),
            ),
          ),
        const SizedBox(height: Spacing.lg),
        ShareMenuGroup(
          items: [
            ShareMenuItem(
              title: context.strings.albumLayout,
              subtitle: _getLayoutDisplayName(
                collection.pubMagicMetadata.layout,
                context,
              ),
              icon: HugeIcons.strokeRoundedGridView,
              showChevron: true,
              onTap: () async {
                await routeToPage(context, LayoutPickerPage(collection));
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        ShareMenuGroup(
          items: [
            ShareMenuItem(
              key: ValueKey("Allow collect ${url.enableCollect}"),
              title: context.strings.allowAddingPhotos,
              icon: HugeIcons.strokeRoundedImageAdd01,
              trailing: ToggleSwitchComponent(
                selected: url.enableCollect,
                onChanged: (selected) async {
                  await _updateUrlSettings(context, {
                    'enableCollect': selected,
                  });
                },
              ),
            ),
            ShareMenuItem(
              key: ValueKey("Allow downloads ${url.enableDownload}"),
              title: context.strings.downloadPhotos,
              icon: HugeIcons.strokeRoundedDownload04,
              trailing: ToggleSwitchComponent(
                selected: url.enableDownload,
                onChanged: (selected) async {
                  await _updateUrlSettings(context, {
                    'enableDownload': selected,
                  });
                  if (!selected) {
                    if (!context.mounted) return;
                    unawaited(
                      showErrorDialog(
                        context,
                        context.strings.disableDownloadWarningTitle,
                        context.strings.disableDownloadWarningBody,
                      ),
                    );
                  }
                },
              ),
            ),
            ShareMenuItem(
              key: ValueKey("Enable comment ${url.enableComment}"),
              title: context.strings.commentAndReact,
              icon: HugeIcons.strokeRoundedMessage01,
              trailing: ToggleSwitchComponent(
                selected: url.enableComment,
                onChanged: (selected) async {
                  await _updateUrlSettings(context, {
                    'enableComment': selected,
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        ShareMenuGroup(
          items: [
            ShareMenuItem(
              key: ValueKey("Allow join ${url.enableJoin}"),
              title: context.strings.allowJoining,
              subtitle: url.enableDownload
                  ? context.strings.allowJoiningDescription
                  : context.strings.enableDownloadsToAllowJoining,
              icon: HugeIcons.strokeRoundedUserAdd01,
              trailing: ToggleSwitchComponent(
                selected: url.enableJoin,
                onChanged: url.enableDownload
                    ? (selected) =>
                          _updateUrlSettings(context, {'enableJoin': selected})
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        ShareMenuGroup(
          items: [
            ShareMenuItem(
              title: context.strings.linkExpiry,
              subtitle: (url.hasExpiry
                  ? (url.isExpired
                        ? context.strings.linkExpired
                        : context.strings.linkEnabled)
                  : context.strings.linkNeverExpires),
              titleMaxLines: 1,
              icon: HugeIcons.strokeRoundedCalendar03,
              showChevron: true,
              onTap: () async {
                await _showLinkExpirySheet(context, url);
              },
            ),
            ShareMenuItem(
              key: ValueKey("Password lock ${url.passwordEnabled}"),
              title: context.strings.password,
              icon: HugeIcons.strokeRoundedSquareLock01,
              trailing: ToggleSwitchComponent(
                selected: url.passwordEnabled,
                onChanged: (selected) async {
                  if (selected) {
                    unawaited(
                      showTextInputDialog(
                        context,
                        title: context.strings.setAPassword,
                        submitButtonLabel: context.strings.lockButtonLabel,
                        hintText: context.strings.enterPassword,
                        isPasswordInput: true,
                        alwaysShowSuccessState: true,
                        onSubmit: (String password) async {
                          if (password.trim().isNotEmpty) {
                            final propToUpdate = await _getEncryptedPassword(
                              password,
                            );
                            if (!context.mounted) return;
                            await _updateUrlSettings(
                              context,
                              propToUpdate,
                              showProgressDialog: false,
                            );
                          }
                        },
                      ),
                    );
                  } else {
                    await _updateUrlSettings(context, {
                      'disablePassword': true,
                    });
                  }
                },
              ),
            ),
            ShareMenuItem(
              title: context.strings.linkDeviceLimit,
              subtitle: url.deviceLimit == 0
                  ? context.strings.noLimit
                  : "${url.deviceLimit}",
              icon: HugeIcons.strokeRoundedLaptop,
              showChevron: true,
              onTap: () async {
                await _showDeviceLimitSheet(context, url);
              },
            ),
          ],
        ),
        if (url.hasExpiry)
          ShareSectionDescription(
            url.isExpired
                ? context.strings.expiredLinkInfo
                : context.strings.linkExpiresOn(
                    expiryTime: getFormattedTime(
                      DateTime.fromMicrosecondsSinceEpoch(url.validTill),
                      context: context,
                    ),
                  ),
          ),
        const SizedBox(height: Spacing.lg),
        ShareMenuGroup(
          items: [
            ShareMenuItem(
              title: context.strings.removeLink,
              icon: HugeIcons.strokeRoundedMinusSignCircle,
              isDestructive: true,
              onTap: () async {
                final bool result = await sharingActions.disableUrl(
                  context,
                  collection,
                );
                if (result && context.mounted) {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  if (collection.isQuickLinkCollection()) {
                    navigator.pop();
                  }
                }
              },
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
      ],
    );
  }

  String _getLayoutDisplayName(String? layout, BuildContext context) {
    return switch (normalizePublicLinkLayout(layout)) {
      'trip' => context.strings.layoutTrip,
      'grouped' => context.strings.layoutGrouped,
      _ => context.strings.layoutMasonry,
    };
  }

  Future<void> _showLinkExpirySheet(BuildContext context, PublicURL url) async {
    final l10n = context.strings;
    final expiryOptions = [
      (title: l10n.never, expireAfterInMicroseconds: 0),
      (
        title: l10n.after1Hour,
        expireAfterInMicroseconds: const Duration(hours: 1).inMicroseconds,
      ),
      (
        title: l10n.after1Day,
        expireAfterInMicroseconds: const Duration(days: 1).inMicroseconds,
      ),
      (
        title: l10n.after1Week,
        expireAfterInMicroseconds: const Duration(days: 7).inMicroseconds,
      ),
      (
        title: l10n.after1Month,
        expireAfterInMicroseconds: const Duration(days: 30).inMicroseconds,
      ),
      (
        title: l10n.after1Year,
        expireAfterInMicroseconds: const Duration(days: 365).inMicroseconds,
      ),
      (title: l10n.custom, expireAfterInMicroseconds: -1),
    ];
    final selectedExpiryOption = _selectedExpiryOption(
      url,
      expiryOptions.map((option) => option.expireAfterInMicroseconds),
    );

    await showBottomSheetComponent<void>(
      context: context,
      builder: (sheetContext) => BottomSheetComponent(
        title: l10n.linkExpiry,
        content: MenuGroupComponent(
          items: [
            for (final expiryOption in expiryOptions)
              MenuComponent(
                key: ValueKey(expiryOption.expireAfterInMicroseconds),
                title: expiryOption.title,
                trailing:
                    selectedExpiryOption ==
                        expiryOption.expireAfterInMicroseconds
                    ? shareCheck(sheetContext)
                    : null,
                showOnlyLoadingState:
                    expiryOption.expireAfterInMicroseconds != -1,
                onTap: () async {
                  if (expiryOption.expireAfterInMicroseconds < 0) {
                    Navigator.of(sheetContext).pop();
                    await _pickCustomExpiry(context);
                    return;
                  }

                  final newValidTill = _validTillForExpiryOption(
                    expiryOption.expireAfterInMicroseconds,
                  );
                  await _updateUrlSettings(
                    context,
                    {'validTill': newValidTill},
                    showProgressDialog: false,
                    showToast: false,
                  );
                  if (sheetContext.mounted) {
                    Navigator.of(sheetContext).pop();
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCustomExpiry(BuildContext context) async {
    final now = DateTime.now();
    final DateTime? picked = await showDateTimePickerSheet(
      context,
      initialDateTime: now,
      minDateTime: now,
    );
    final timeInMicrosecondsFromEpoch = picked?.microsecondsSinceEpoch;
    if (timeInMicrosecondsFromEpoch == null) {
      return;
    }

    if (!context.mounted) return;
    await _updateUrlSettings(
      context,
      {'validTill': timeInMicrosecondsFromEpoch},
      showProgressDialog: false,
      showToast: false,
    );
  }

  int _validTillForExpiryOption(int expireAfterInMicroseconds) {
    if (expireAfterInMicroseconds == 0) {
      return 0;
    }
    return DateTime.now().microsecondsSinceEpoch + expireAfterInMicroseconds;
  }

  int _selectedExpiryOption(PublicURL url, Iterable<int> expireAfterOptions) {
    if (!url.hasExpiry) {
      return 0;
    }

    final remainingMicroseconds =
        url.validTill - DateTime.now().microsecondsSinceEpoch;
    if (remainingMicroseconds <= 0) {
      return -1;
    }

    for (final expireAfterOption in expireAfterOptions) {
      if (expireAfterOption <= 0) {
        continue;
      }
      final difference = (remainingMicroseconds - expireAfterOption).abs();
      if (difference <= _expiryPresetSelectionTolerance.inMicroseconds) {
        return expireAfterOption;
      }
    }

    return -1;
  }

  Future<void> _showDeviceLimitSheet(
    BuildContext context,
    PublicURL url,
  ) async {
    final l10n = context.strings;
    final currentDeviceLimit = url.deviceLimit;
    final deviceLimits = [
      if (!publicLinkDeviceLimits.contains(currentDeviceLimit))
        currentDeviceLimit,
      ...publicLinkDeviceLimits,
    ];

    await showBottomSheetComponent<void>(
      context: context,
      builder: (sheetContext) => BottomSheetComponent(
        title: l10n.linkDeviceLimit,
        content: MenuGroupComponent(
          items: [
            for (final deviceLimit in deviceLimits)
              MenuComponent(
                key: ValueKey(deviceLimit),
                title: deviceLimit == 0 ? l10n.noLimit : "$deviceLimit",
                trailing: currentDeviceLimit == deviceLimit
                    ? shareCheck(sheetContext)
                    : null,
                showOnlyLoadingState: true,
                onTap: () async {
                  await _updateUrlSettings(
                    context,
                    {'deviceLimit': deviceLimit},
                    showProgressDialog: false,
                    showToast: false,
                  );
                  if (sheetContext.mounted) {
                    Navigator.of(sheetContext).pop();
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _getEncryptedPassword(String pass) async {
    final kekSalt = CryptoUtil.getSaltToDeriveKey();
    final result = await CryptoUtil.deriveInteractiveKey(
      utf8.encode(pass),
      kekSalt,
    );
    return {
      'passHash': CryptoUtil.bin2base64(result.key),
      'nonce': CryptoUtil.bin2base64(kekSalt),
      'memLimit': result.memLimit,
      'opsLimit': result.opsLimit,
    };
  }

  Future<void> _updateUrlSettings(
    BuildContext context,
    Map<String, dynamic> prop, {
    bool showProgressDialog = true,
    bool showToast = true,
  }) async {
    final dialog = showProgressDialog
        ? createProgressDialog(context, context.strings.pleaseWait)
        : null;
    await dialog?.show();
    try {
      await CollectionsService.instance.updateShareUrl(widget.collection, prop);
      await dialog?.hide();
      if (context.mounted) {
        if (showToast) showShortToast(context, context.strings.albumUpdated);
        setState(() {});
      }
    } catch (e) {
      await dialog?.hide();
      if (e is LinkEditNotAllowedError) {
        if (context.mounted) {
          await _showLinkEditNotAllowedDialog(context);
        }
      } else {
        if (context.mounted) {
          await showGenericErrorDialog(context: context, error: e);
        }
      }
      rethrow;
    }
  }

  Future<void> _showLinkEditNotAllowedDialog(BuildContext context) async {
    final buttonResult = await showDialogWidget(
      context: context,
      title: context.strings.sorry,
      body: context.strings.subscribeToChangeLinkSetting,
      buttons: [
        ButtonWidget(
          buttonType: ButtonType.primary,
          isInAlert: true,
          shouldStickToDarkTheme: true,
          buttonAction: ButtonAction.first,
          labelText: context.strings.subscribe,
        ),
        ButtonWidget(
          buttonType: ButtonType.secondary,
          buttonAction: ButtonAction.cancel,
          isInAlert: true,
          shouldStickToDarkTheme: true,
          labelText: context.strings.ok,
        ),
      ],
    );
    if (buttonResult?.action == ButtonAction.first) {
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (BuildContext context) {
            return getSubscriptionPage();
          },
        ),
      );
    }
  }
}

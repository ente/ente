import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_crypto/ente_crypto.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:ente_qr_ui/ente_qr_ui.dart';
import 'package:flutter/material.dart';
import "package:flutter/services.dart";
import 'package:hugeicons/hugeicons.dart';
import 'package:photos/core/constants.dart';
import "package:photos/core/errors.dart";
import "package:photos/gateways/collections/models/public_url.dart";
import "package:photos/generated/l10n.dart";
import 'package:photos/models/collection/collection.dart';
import 'package:photos/services/collections_service.dart';
import 'package:photos/ui/actions/collection/collection_sharing_actions.dart';
import 'package:photos/ui/components/buttons/button_widget.dart';
import 'package:photos/ui/components/dialog_widget.dart';
import 'package:photos/ui/components/models/button_type.dart';
import 'package:photos/ui/notification/toast.dart';
import 'package:photos/ui/payment/subscription.dart';
import 'package:photos/ui/sharing/pickers/layout_picker_page.dart';
import 'package:photos/ui/sharing/share_components.dart';
import 'package:photos/ui/viewer/date/date_time_picker.dart';
import 'package:photos/utils/dialog_util.dart';
import 'package:photos/utils/public_link_layout_util.dart';
import "package:photos/utils/share_util.dart";

class ManageSharedLinkWidget extends StatefulWidget {
  final Collection? collection;

  const ManageSharedLinkWidget({super.key, this.collection});

  @override
  State<ManageSharedLinkWidget> createState() => _ManageSharedLinkWidgetState();
}

class _ManageSharedLinkWidgetState extends State<ManageSharedLinkWidget> {
  static const Duration _expiryPresetSelectionTolerance = Duration(minutes: 5);

  final CollectionActions sharingActions = CollectionActions(
    CollectionsService.instance,
  );
  final GlobalKey sendLinkButtonKey = GlobalKey();

  String _getLayoutDisplayName(String? layout, BuildContext context) {
    final normalizedLayout = normalizePublicLinkLayout(layout);
    switch (normalizedLayout) {
      case 'masonry':
        return AppLocalizations.of(context).layoutMasonry;
      case 'trip':
        return AppLocalizations.of(context).layoutTrip;
      case 'grouped':
        return AppLocalizations.of(context).layoutGrouped;
      default:
        return AppLocalizations.of(context).layoutMasonry;
    }
  }

  @override
  Widget build(BuildContext context) {
    final collection = widget.collection!;
    final isCollectEnabled =
        collection.publicURLs.firstOrNull?.enableCollect ?? false;
    final isDownloadEnabled =
        collection.publicURLs.firstOrNull?.enableDownload ?? true;
    final isPasswordEnabled =
        collection.publicURLs.firstOrNull?.passwordEnabled ?? false;
    final isJoinEnabled = collection.publicURLs.firstOrNull?.enableJoin ?? true;
    final enableComment =
        collection.publicURLs.firstOrNull?.enableComment ?? false;
    final PublicURL url = collection.publicURLs.firstOrNull!;
    final String urlValue = CollectionsService.instance.getPublicUrl(
      collection,
    );
    final colors = context.componentColors;

    return ShareScaffold(
      title: AppLocalizations.of(context).manageLink,
      children: [
        ShareMenuGroup(
          items: [
            ShareMenuItem(
              title: AppLocalizations.of(context).albumLayout,
              subtitle: _getLayoutDisplayName(
                collection.pubMagicMetadata.layout ?? "masonry",
                context,
              ),
              icon: HugeIcons.strokeRoundedLayoutTable01,
              showChevron: true,
              onTap: () async {
                unawaited(
                  routeToPage(context, LayoutPickerPage(collection)).then((
                    value,
                  ) {
                    setState(() {});
                  }),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        ShareMenuGroup(
          items: [
            ShareMenuItem(
              key: ValueKey("Allow collect $isCollectEnabled"),
              title: AppLocalizations.of(context).allowAddingPhotos,
              icon: HugeIcons.strokeRoundedImageAdd01,
              trailing: ToggleSwitchComponent(
                selected: isCollectEnabled,
                onChanged: (selected) async {
                  await _updateUrlSettings(context, {
                    'enableCollect': selected,
                  });
                },
              ),
            ),
            ShareMenuItem(
              key: ValueKey("Enable comment $enableComment"),
              title: AppLocalizations.of(context).enableComment,
              icon: HugeIcons.strokeRoundedComment01,
              trailing: ToggleSwitchComponent(
                selected: enableComment,
                onChanged: (selected) async {
                  await _updateUrlSettings(context, {
                    'enableComment': selected,
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        ShareMenuGroup(
          items: [
            ShareMenuItem(
              title: AppLocalizations.of(context).linkExpiry,
              subtitle: (url.hasExpiry
                  ? (url.isExpired
                        ? AppLocalizations.of(context).linkExpired
                        : AppLocalizations.of(context).linkEnabled)
                  : AppLocalizations.of(context).linkNeverExpires),
              titleMaxLines: 1,
              icon: HugeIcons.strokeRoundedCalendar03,
              showChevron: true,
              onTap: () async {
                await _showLinkExpirySheet(context, url);
              },
            ),
          ],
        ),
        if (url.hasExpiry) ...[
          ShareSectionDescription(
            url.isExpired
                ? AppLocalizations.of(context).expiredLinkInfo
                : AppLocalizations.of(context).linkExpiresOn(
                    expiryTime: getFormattedTime(
                      DateTime.fromMicrosecondsSinceEpoch(url.validTill),
                      context: context,
                    ),
                  ),
          ),
          const SizedBox(height: Spacing.sm),
        ],
        const SizedBox(height: Spacing.sm),
        ShareMenuGroup(
          items: [
            ShareMenuItem(
              title: AppLocalizations.of(context).linkDeviceLimit,
              subtitle: url.deviceLimit == 0
                  ? AppLocalizations.of(context).noDeviceLimit
                  : "${url.deviceLimit}",
              icon: HugeIcons.strokeRoundedLaptop,
              showChevron: true,
              onTap: () async {
                await _showDeviceLimitSheet(context, url);
              },
            ),
            ShareMenuItem(
              key: ValueKey("Allow downloads $isDownloadEnabled"),
              title: AppLocalizations.of(context).allowDownloads,
              icon: HugeIcons.strokeRoundedDownload04,
              trailing: ToggleSwitchComponent(
                selected: isDownloadEnabled,
                onChanged: (selected) async {
                  await _updateUrlSettings(context, {
                    'enableDownload': selected,
                  });
                  if (!selected) {
                    if (!context.mounted) return;
                    unawaited(
                      showErrorDialog(
                        context,
                        AppLocalizations.of(
                          context,
                        ).disableDownloadWarningTitle,
                        AppLocalizations.of(context).disableDownloadWarningBody,
                      ),
                    );
                  }
                },
              ),
            ),
            ShareMenuItem(
              key: ValueKey("Allow join $isJoinEnabled"),
              title: AppLocalizations.of(context).allowJoiningAlbum,
              icon: HugeIcons.strokeRoundedUserMultiple,
              trailing: ToggleSwitchComponent(
                selected: isJoinEnabled,
                onChanged: (selected) async {
                  await _updateUrlSettings(context, {'enableJoin': selected});
                },
              ),
            ),
            ShareMenuItem(
              key: ValueKey("Password lock $isPasswordEnabled"),
              title: AppLocalizations.of(context).passwordLock,
              icon: HugeIcons.strokeRoundedLockPassword,
              trailing: ToggleSwitchComponent(
                selected: isPasswordEnabled,
                onChanged: (selected) async {
                  if (selected) {
                    unawaited(
                      showTextInputDialog(
                        context,
                        title: AppLocalizations.of(context).setAPassword,
                        submitButtonLabel: AppLocalizations.of(
                          context,
                        ).lockButtonLabel,
                        hintText: AppLocalizations.of(context).enterPassword,
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
          ],
        ),
        const SizedBox(height: Spacing.sm),
        ShareMenuGroup(items: _linkActionItems(context, url, urlValue)),
        const SizedBox(height: Spacing.sm),
        ShareMenuGroup(
          items: [
            ShareMenuItem(
              title: AppLocalizations.of(context).removeLink,
              leading: Icon(Icons.remove_circle_outline, color: colors.warning),
              isDestructive: true,
              onTap: () async {
                final bool result = await sharingActions.disableUrl(
                  context,
                  collection,
                );
                if (result && mounted) {
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                  if (collection.isQuickLinkCollection()) {
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
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

  List<Widget> _linkActionItems(
    BuildContext context,
    PublicURL url,
    String urlValue,
  ) {
    if (url.isExpired) {
      return [
        ShareMenuItem(
          title: AppLocalizations.of(context).linkHasExpired,
          leading: const Icon(Icons.error_outline_rounded),
          isDestructive: true,
          isDisabled: true,
        ),
      ];
    }

    return [
      ShareMenuItem(
        title: AppLocalizations.of(context).copyLink,
        icon: HugeIcons.strokeRoundedCopy01,
        showOnlyLoadingState: true,
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: urlValue));
          if (!context.mounted) return;
          showShortToast(
            context,
            AppLocalizations.of(context).linkCopiedToClipboard,
          );
        },
      ),
      ShareMenuItem(
        title: AppLocalizations.of(context).copyEmbedHtml,
        leading: const Icon(Icons.code_rounded),
        onTap: () async {
          final embedHtml = CollectionsService.instance.getEmbedHtml(
            widget.collection!,
          );
          await Clipboard.setData(ClipboardData(text: embedHtml));
          if (!context.mounted) return;
          showShortToast(
            context,
            AppLocalizations.of(context).linkCopiedToClipboard,
          );
        },
      ),
      ShareMenuItem(
        key: sendLinkButtonKey,
        title: AppLocalizations.of(context).sendLink,
        icon: HugeIcons.strokeRoundedSent,
        onTap: () async {
          await shareAlbumLink(context, urlValue, sendLinkButtonKey);
        },
      ),
      ShareMenuItem(
        title: AppLocalizations.of(context).sendQrCode,
        icon: HugeIcons.strokeRoundedQrCode,
        onTap: () async {
          await showDialog<void>(
            context: context,
            builder: (BuildContext dialogContext) {
              return QrCodeDialog(
                data: urlValue,
                title: widget.collection!.displayName,
                accentColor: const Color(0xFF08C225),
                shareFileName: 'ente_qr_${widget.collection!.displayName}.png',
                shareText:
                    'Scan this QR code to view my ${widget.collection!.displayName} album on ente',
                dialogTitle: AppLocalizations.of(context).qrCode,
                shareButtonText: AppLocalizations.of(context).share,
                logoAssetPath: 'assets/qr_logo.png',
                branding: const QrTextBranding(
                  text: 'ente',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Montserrat',
                  ),
                ),
              );
            },
          );
        },
      ),
    ];
  }

  Future<void> _showLinkExpirySheet(BuildContext context, PublicURL url) async {
    final l10n = AppLocalizations.of(context);
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
                  await _updateShareUrlFromPicker(context, {
                    'validTill': newValidTill,
                  });
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
    final DateTime? picked = await showDatePickerSheet(
      context,
      initialDate: now,
      minDate: now,
    );
    final timeInMicrosecondsFromEpoch = picked?.microsecondsSinceEpoch;
    if (timeInMicrosecondsFromEpoch == null) {
      return;
    }

    if (!context.mounted) return;
    await _updateShareUrlFromPicker(context, {
      'validTill': timeInMicrosecondsFromEpoch,
    });
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
    final l10n = AppLocalizations.of(context);
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
                title: deviceLimit == 0 ? l10n.noDeviceLimit : "$deviceLimit",
                trailing: currentDeviceLimit == deviceLimit
                    ? shareCheck(sheetContext)
                    : null,
                showOnlyLoadingState: true,
                onTap: () async {
                  await _updateShareUrlFromPicker(context, {
                    'deviceLimit': deviceLimit,
                  });
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

  Future<void> _updateShareUrlFromPicker(
    BuildContext context,
    Map<String, dynamic> prop,
  ) async {
    try {
      await CollectionsService.instance.updateShareUrl(
        widget.collection!,
        prop,
      );
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
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
  }) async {
    final dialog = showProgressDialog
        ? createProgressDialog(context, AppLocalizations.of(context).pleaseWait)
        : null;
    await dialog?.show();
    try {
      await CollectionsService.instance.updateShareUrl(
        widget.collection!,
        prop,
      );
      await dialog?.hide();
      if (context.mounted) {
        showShortToast(context, AppLocalizations.of(context).albumUpdated);
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
      title: AppLocalizations.of(context).sorry,
      body: AppLocalizations.of(context).subscribeToChangeLinkSetting,
      buttons: [
        ButtonWidget(
          buttonType: ButtonType.primary,
          isInAlert: true,
          shouldStickToDarkTheme: true,
          buttonAction: ButtonAction.first,
          labelText: AppLocalizations.of(context).subscribe,
        ),
        ButtonWidget(
          buttonType: ButtonType.secondary,
          buttonAction: ButtonAction.cancel,
          isInAlert: true,
          shouldStickToDarkTheme: true,
          labelText: AppLocalizations.of(context).ok,
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

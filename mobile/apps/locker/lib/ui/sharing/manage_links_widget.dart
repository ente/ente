import "dart:async";
import "dart:convert";

import 'package:ente_components/ente_components.dart';
import "package:ente_crypto_api/ente_crypto_api.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_ui/components/captioned_text_widget_v2.dart";
import "package:ente_ui/components/divider_widget.dart";
import "package:ente_ui/components/menu_item_widget_v2.dart";
import "package:ente_ui/components/toggle_switch_widget.dart";
import "package:ente_ui/utils/dialog_util.dart";
import "package:ente_ui/utils/toast_util.dart";
import "package:ente_utils/share_utils.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/l10n/l10n.dart";
import "package:locker/services/collections/collections_api_client.dart";
import "package:locker/services/collections/collections_service.dart";
import "package:locker/services/collections/models/collection.dart";
import "package:locker/services/collections/models/public_url.dart";
import "package:locker/ui/components/text_input_sheet.dart";
import "package:locker/ui/sharing/pickers/device_limit_picker_page.dart";
import "package:locker/ui/sharing/pickers/link_expiry_picker_page.dart";
import "package:locker/utils/collection_actions.dart";
import "package:locker/utils/error_sheet.dart";

class ManageSharedLinkWidget extends StatefulWidget {
  final Collection? collection;

  const ManageSharedLinkWidget({super.key, this.collection});

  @override
  State<ManageSharedLinkWidget> createState() => _ManageSharedLinkWidgetState();
}

class _ManageSharedLinkWidgetState extends State<ManageSharedLinkWidget> {
  final GlobalKey sendLinkButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final PublicURL url = widget.collection!.publicURLs.firstOrNull!;
    final String urlValue = CollectionService.instance.getPublicUrl(
      widget.collection!,
    );
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        centerTitle: false,
        title: Text(context.l10n.manageLink),
      ),
      body: SingleChildScrollView(
        child: ListBody(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MenuItemWidgetV2(
                    alignCaptionedTextToLeft: true,
                    captionedTextWidget: CaptionedTextWidgetV2(
                      title: context.l10n.linkExpiry,
                      subTitle: url.hasExpiry
                          ? (url.isExpired
                                ? context.l10n.linkExpired
                                : getFormattedTime(
                                    DateTime.fromMicrosecondsSinceEpoch(
                                      url.validTill,
                                    ),
                                  ))
                          : context.l10n.never,
                      subTitleColor: url.isExpired ? colors.warning : null,
                    ),
                    trailingWidget: HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowRight01,
                      color: colors.textLight,
                      size: 20,
                    ),
                    menuItemColor: colors.fillLight,
                    surfaceExecutionStates: false,
                    onTap: () async {
                      unawaited(
                        routeToPage(
                          context,
                          LinkExpiryPickerPage(widget.collection!),
                        ).then((value) {
                          if (mounted) {
                            setState(() {});
                          }
                        }),
                      );
                    },
                  ),
                  const Padding(padding: EdgeInsets.only(top: 24)),
                  MenuItemWidgetV2(
                    captionedTextWidget: CaptionedTextWidgetV2(
                      title: context.l10n.linkDeviceLimit,
                      subTitle: url.deviceLimit == 0
                          ? context.l10n.noDeviceLimit
                          : "${url.deviceLimit}",
                    ),
                    trailingWidget: HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowRight01,
                      color: colors.textLight,
                      size: 20,
                    ),
                    menuItemColor: colors.fillLight,
                    alignCaptionedTextToLeft: true,
                    isBottomBorderRadiusRemoved: true,
                    onTap: () async {
                      unawaited(
                        routeToPage(
                          context,
                          DeviceLimitPickerPage(widget.collection!),
                        ).then((value) {
                          if (mounted) {
                            setState(() {});
                          }
                        }),
                      );
                    },
                    surfaceExecutionStates: false,
                  ),
                  DividerWidget(
                    dividerType: DividerType.menu,
                    bgColor: colors.fillLight,
                  ),
                  MenuItemWidgetV2(
                    key: ValueKey("Password lock ${url.passwordEnabled}"),
                    captionedTextWidget: CaptionedTextWidgetV2(
                      title: context.l10n.passwordLock,
                    ),
                    alignCaptionedTextToLeft: true,
                    isTopBorderRadiusRemoved: true,
                    menuItemColor: colors.fillLight,
                    trailingWidget: ToggleSwitchWidget(
                      value: () => url.passwordEnabled,
                      onChanged: () async {
                        if (!url.passwordEnabled) {
                          await showTextInputSheet(
                            context,
                            title: context.l10n.setAPassword,
                            submitButtonLabel: context.l10n.lockButtonLabel,
                            hintText: context.l10n.enterPassword,
                            onSubmit: (String password) async {
                              if (password.trim().isEmpty) {
                                return;
                              }
                              final propToUpdate = await _getEncryptedPassword(
                                password,
                              );
                              await _updateUrlSettings(
                                context.mounted ? context : null,
                                propToUpdate,
                                showProgressDialog: false,
                              );
                            },
                            isPasswordInput: true,
                            textCapitalization: TextCapitalization.none,
                            maxLength: 256,
                          );
                        } else {
                          await _updateUrlSettings(context, {
                            'disablePassword': true,
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (url.isExpired)
                    MenuItemWidgetV2(
                      captionedTextWidget: CaptionedTextWidgetV2(
                        title: context.l10n.linkExpired,
                        textColor: colors.warning,
                      ),
                      leadingIcon: Icons.error_outline,
                      leadingIconColor: colors.warning,
                      menuItemColor: colors.fillLight,
                    ),
                  if (!url.isExpired)
                    MenuItemWidgetV2(
                      captionedTextWidget: CaptionedTextWidgetV2(
                        title: context.l10n.copyLink,
                        makeTextBold: true,
                      ),
                      leadingIconWidget: HugeIcon(
                        icon: HugeIcons.strokeRoundedCopy01,
                        color: colors.textBase,
                        size: 20,
                      ),
                      menuItemColor: colors.fillLight,
                      showOnlyLoadingState: true,
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: urlValue));
                        if (!context.mounted) {
                          return;
                        }
                        showShortToast(
                          context,
                          context.l10n.linkCopiedToClipboard,
                        );
                      },
                      isBottomBorderRadiusRemoved: true,
                    ),
                  if (!url.isExpired)
                    DividerWidget(
                      dividerType: DividerType.menu,
                      bgColor: colors.fillLight,
                    ),
                  if (!url.isExpired)
                    MenuItemWidgetV2(
                      key: sendLinkButtonKey,
                      captionedTextWidget: CaptionedTextWidgetV2(
                        title: context.l10n.sendLink,
                        makeTextBold: true,
                      ),
                      leadingIconWidget: HugeIcon(
                        icon: HugeIcons.strokeRoundedShare08,
                        color: colors.textBase,
                        size: 20,
                      ),
                      menuItemColor: colors.fillLight,
                      onTap: () async {
                        unawaited(shareText(urlValue, context: context));
                      },
                      isTopBorderRadiusRemoved: true,
                    ),
                  const SizedBox(height: 24),
                  MenuItemWidgetV2(
                    captionedTextWidget: CaptionedTextWidgetV2(
                      title: context.l10n.removeLink,
                      textColor: colors.warning,
                      makeTextBold: true,
                    ),
                    leadingIconWidget: HugeIcon(
                      icon: HugeIcons.strokeRoundedDelete02,
                      color: colors.warning,
                      size: 20,
                    ),
                    menuItemColor: colors.fillLight,
                    surfaceExecutionStates: false,
                    onTap: () async {
                      final bool result = await CollectionActions.disableUrl(
                        context,
                        widget.collection!,
                      );
                      if (!context.mounted || !result) {
                        return;
                      }
                      Navigator.of(context).pop();
                      if (widget.collection!.isQuickLinkCollection()) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ],
              ),
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
    BuildContext? context,
    Map<String, dynamic> prop, {
    bool showProgressDialog = true,
  }) async {
    final dialog = showProgressDialog && context != null && context.mounted
        ? createProgressDialog(context, context.l10n.pleaseWait)
        : null;
    await dialog?.show();
    try {
      await CollectionApiClient.instance.updateShareUrl(
        widget.collection!,
        prop,
      );
      await dialog?.hide();
      if (context != null && context.mounted) {
        showShortToast(context, context.l10n.collectionUpdated);
      }
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      await dialog?.hide();
      if (context != null && context.mounted) {
        await showLockerErrorSheet(context, e);
      }
      rethrow;
    }
  }
}

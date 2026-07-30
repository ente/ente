import "dart:async";
import "dart:convert";

import 'package:ente_components/ente_components.dart';
import "package:ente_crypto_api/ente_crypto_api.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
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
      backgroundColor: colors.backgroundBase,
      body: AppBarComponent(
        title: context.l10n.manageLink,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.md,
              Spacing.lg,
              Spacing.md,
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  MenuGroupComponent(
                    items: [
                      MenuComponent(
                        title: context.l10n.linkExpiry,
                        subtitle: url.hasExpiry
                            ? (url.isExpired
                                  ? context.l10n.linkExpired
                                  : getFormattedTime(
                                      DateTime.fromMicrosecondsSinceEpoch(
                                        url.validTill,
                                      ),
                                    ))
                            : context.l10n.never,
                        subtitleColor: url.isExpired ? colors.warning : null,
                        trailing: HugeIcon(
                          icon: HugeIcons.strokeRoundedArrowRight01,
                          color: colors.textLight,
                          size: 20,
                        ),
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
                    ],
                  ),
                  const SizedBox(height: Spacing.xxl),
                  MenuGroupComponent(
                    items: [
                      MenuComponent(
                        title: context.l10n.linkDeviceLimit,
                        subtitle: url.deviceLimit == 0
                            ? context.l10n.noDeviceLimit
                            : "${url.deviceLimit}",
                        trailing: HugeIcon(
                          icon: HugeIcons.strokeRoundedArrowRight01,
                          color: colors.textLight,
                          size: 20,
                        ),
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
                      ),
                      MenuComponent(
                        key: ValueKey("Password lock ${url.passwordEnabled}"),
                        title: context.l10n.passwordLock,
                        trailing: ToggleSwitchComponent.async(
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
                                  final propToUpdate =
                                      await _getEncryptedPassword(password);
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
                    ],
                  ),
                  const SizedBox(height: Spacing.xxl),
                  MenuGroupComponent(
                    items: [
                      if (url.isExpired)
                        MenuComponent(
                          title: context.l10n.linkExpired,
                          titleColor: colors.warning,
                          iconColor: colors.warning,
                          leading: const Icon(Icons.error_outline),
                        ),
                      if (!url.isExpired)
                        MenuComponent(
                          title: context.l10n.copyLink,
                          titleBold: true,
                          leading: HugeIcon(
                            icon: HugeIcons.strokeRoundedCopy01,
                            color: colors.textBase,
                            size: 20,
                          ),
                          showOnlyLoadingState: true,
                          onTap: () async {
                            await Clipboard.setData(
                              ClipboardData(text: urlValue),
                            );
                            if (!context.mounted) {
                              return;
                            }
                            showShortToast(
                              context,
                              context.l10n.linkCopiedToClipboard,
                            );
                          },
                        ),
                      if (!url.isExpired)
                        MenuComponent(
                          key: sendLinkButtonKey,
                          title: context.l10n.sendLink,
                          titleBold: true,
                          leading: HugeIcon(
                            icon: HugeIcons.strokeRoundedShare08,
                            color: colors.textBase,
                            size: 20,
                          ),
                          onTap: () async {
                            unawaited(shareText(urlValue, context: context));
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: Spacing.xxl),
                  MenuGroupComponent(
                    items: [
                      MenuComponent(
                        title: context.l10n.removeLink,
                        titleBold: true,
                        titleColor: colors.warning,
                        iconColor: colors.warning,
                        leading: HugeIcon(
                          icon: HugeIcons.strokeRoundedDelete02,
                          color: colors.warning,
                          size: 20,
                        ),
                        onTap: () async {
                          final bool result =
                              await CollectionActions.disableUrl(
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
                ],
              ),
            ),
          ),
        ],
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

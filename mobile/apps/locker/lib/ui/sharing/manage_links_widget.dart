import "dart:async";
import "dart:convert";

import 'package:ente_components/ente_components.dart';
import "package:ente_crypto_api/ente_crypto_api.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/utils/toast_util.dart";
import "package:ente_utils/share_utils.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/services/collections/collections_api_client.dart";
import "package:locker/services/collections/collections_service.dart";
import "package:locker/services/collections/models/collection.dart";
import "package:locker/services/collections/models/public_url.dart";
import "package:locker/ui/components/locker_progress_dialog.dart";
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
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final PublicURL url = widget.collection!.publicURLs.firstOrNull!;
    Widget linkIcon(List<List<dynamic>> icon, {Color? color}) => HugeIcon(
      icon: icon,
      color: color ?? colors.textLight,
      size: IconSizes.small,
      strokeWidth: 1.6,
    );
    final chevron = Icon(
      Icons.chevron_right_rounded,
      color: colors.textLight,
      size: IconSizes.medium,
    );
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: AppBarComponent(
        title: context.strings.linkSettings,
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverSafeArea(
            top: false,
            sliver: SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                0,
                Spacing.lg,
                Spacing.xl,
              ),
              sliver: SliverList.list(
                children: [
                  _LinkSettingsGroup(
                    items: [
                      if (url.isExpired)
                        MenuComponent(
                          title: context.strings.linkHasExpired,
                          titleColor: colors.warning,
                          isDisabled: true,
                          iconColor: colors.warning,
                          leading: const Icon(Icons.error_outline_rounded),
                        ),
                      if (!url.isExpired) ...[
                        MenuComponent(
                          title: context.strings.copyLink,
                          leading: linkIcon(HugeIcons.strokeRoundedCopy01),
                          showOnlyLoadingState: true,
                          onTap: () async {
                            await Clipboard.setData(
                              ClipboardData(
                                text: CollectionService.instance.getPublicUrl(
                                  widget.collection!,
                                ),
                              ),
                            );
                            if (!context.mounted) {
                              return;
                            }
                            showShortToast(
                              context,
                              context.strings.linkCopiedToClipboard,
                            );
                          },
                        ),
                        MenuComponent(
                          key: sendLinkButtonKey,
                          title: context.strings.sendLink,
                          leading: linkIcon(HugeIcons.strokeRoundedSent),
                          onTap: () async {
                            await shareText(
                              CollectionService.instance.getPublicUrl(
                                widget.collection!,
                              ),
                              context: context,
                              key: sendLinkButtonKey,
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                  if (!url.isExpired)
                    Padding(
                      padding: const EdgeInsets.only(top: Spacing.sm),
                      child: Text(
                        context.strings.publicCollectionLinkAccessDescription,
                        style: TextStyles.mini.copyWith(
                          color: colors.textLight,
                        ),
                      ),
                    ),
                  const SizedBox(height: Spacing.lg),
                  _LinkSettingsGroup(
                    items: [
                      MenuComponent(
                        title: context.strings.linkDeviceLimit,
                        leading: linkIcon(HugeIcons.strokeRoundedLaptop),
                        subtitle: url.deviceLimit == 0
                            ? context.strings.noLimit
                            : "${url.deviceLimit}",
                        trailing: chevron,
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
                        title: context.strings.password,
                        leading: linkIcon(HugeIcons.strokeRoundedSquareLock01),
                        trailing: ToggleSwitchComponent.async(
                          value: () => url.passwordEnabled,
                          onChanged: () async {
                            if (!url.passwordEnabled) {
                              await showTextInputSheet(
                                context,
                                title: context.strings.setAPassword,
                                submitButtonLabel:
                                    context.strings.lockButtonLabel,
                                hintText: context.strings.enterPassword,
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
                      MenuComponent(
                        title: context.strings.linkExpiry,
                        leading: linkIcon(HugeIcons.strokeRoundedCalendar03),
                        subtitle: url.hasExpiry
                            ? (url.isExpired
                                  ? context.strings.linkExpired
                                  : context.strings.linkEnabled)
                            : context.strings.linkNeverExpires,
                        trailing: chevron,
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
                  if (url.hasExpiry)
                    Padding(
                      padding: const EdgeInsets.only(top: Spacing.sm),
                      child: Text(
                        url.isExpired
                            ? context.strings.expiredLinkInfo
                            : context.strings.linkExpiresOn(
                                expiryTime: getFormattedTime(
                                  DateTime.fromMicrosecondsSinceEpoch(
                                    url.validTill,
                                  ),
                                  context: context,
                                ),
                              ),
                        style: TextStyles.body.copyWith(
                          color: colors.textLight,
                        ),
                      ),
                    ),
                  const SizedBox(height: Spacing.lg),
                  _LinkSettingsGroup(
                    items: [
                      MenuComponent(
                        title: context.strings.removeLink,
                        titleColor: colors.warning,
                        iconColor: colors.warning,
                        leading: linkIcon(
                          HugeIcons.strokeRoundedMinusSignCircle,
                          color: colors.warning,
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
                  const SizedBox(height: Spacing.sm),
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
        ? await showLockerProgressDialog(context, context.strings.pleaseWait)
        : null;
    try {
      await CollectionApiClient.instance.updateShareUrl(
        widget.collection!,
        prop,
      );
      await dialog?.hide();
      if (context != null && context.mounted) {
        showShortToast(context, context.strings.collectionUpdated);
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

class _LinkSettingsGroup extends StatelessWidget {
  const _LinkSettingsGroup({required this.items});

  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    return MenuGroupComponent(
      items: items.length > 1
          ? [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var index = 0; index < items.length; index++) ...[
                      items[index],
                      if (index < items.length - 1)
                        const SizedBox(height: Spacing.xs),
                    ],
                  ],
                ),
              ),
            ]
          : items,
    );
  }
}

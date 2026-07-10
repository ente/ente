import 'package:collection/collection.dart';
import 'package:ente_qr_ui/ente_qr_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:photos/generated/l10n.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/services/collections_service.dart';
import 'package:photos/ui/notification/toast.dart';
import 'package:photos/ui/sharing/share_components.dart';
import 'package:photos/utils/share_util.dart';

class PublicLinkEnabledActionsWidget extends StatelessWidget {
  final Collection collection;
  final GlobalKey? sendLinkButtonKey;
  final List<Widget> additionalItems;

  const PublicLinkEnabledActionsWidget({
    super.key,
    required this.collection,
    this.sendLinkButtonKey,
    this.additionalItems = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (!collection.hasLink) {
      return const SizedBox.shrink();
    }

    final bool hasExpired =
        collection.publicURLs.firstOrNull?.isExpired ?? false;
    final items = <Widget>[];

    if (hasExpired) {
      items.add(
        ShareMenuItem(
          title: AppLocalizations.of(context).linkHasExpired,
          leading: const Icon(Icons.error_outline_rounded),
          isDestructive: true,
          isDisabled: true,
        ),
      );
    } else {
      final String url = CollectionsService.instance.getPublicUrl(collection);
      final GlobalKey effectiveKey = sendLinkButtonKey ?? GlobalKey();
      items.addAll([
        ShareMenuItem(
          title: AppLocalizations.of(context).copyLink,
          icon: HugeIcons.strokeRoundedCopy01,
          showOnlyLoadingState: true,
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (!context.mounted) return;
            showShortToast(
              context,
              AppLocalizations.of(context).linkCopiedToClipboard,
            );
          },
        ),
        ShareMenuItem(
          key: effectiveKey,
          title: AppLocalizations.of(context).sendLink,
          icon: HugeIcons.strokeRoundedSent,
          onTap: () async {
            await shareAlbumLink(context, url, effectiveKey);
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
                  data: url,
                  title: collection.displayName,
                  accentColor: const Color(0xFF08C225),
                  shareFileName: 'ente_qr_${collection.displayName}.png',
                  shareText:
                      'Scan this QR code to view my ${collection.displayName} album on ente',
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
      ]);
    }

    items.addAll(additionalItems);
    return ShareMenuGroup(items: items);
  }
}

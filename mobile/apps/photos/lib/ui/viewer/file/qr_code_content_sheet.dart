import "package:ente_qr/ente_qr.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/base_bottom_sheet.dart";
import "package:photos/ui/components/buttons/button_widget_v2.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/utils/share_util.dart";
import "package:url_launcher/url_launcher.dart";

Future<void> showQrCodeContentSheet(
  BuildContext context, {
  required List<QrDetection> detections,
}) {
  return showBaseBottomSheet(
    context,
    title: AppLocalizations.of(context).qrCode,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < detections.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          _QrContentEntry(content: detections[i].content),
        ],
      ],
    ),
  );
}

class _QrContentEntry extends StatelessWidget {
  final String content;

  const _QrContentEntry({required this.content});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final l10n = AppLocalizations.of(context);
    final uri = Uri.tryParse(content);
    final isUrl =
        uri != null && (uri.scheme == "http" || uri.scheme == "https");
    final isUpi = uri != null && uri.scheme == "upi";

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isUpi) ...[
          Stack(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(
                  left: 16,
                  top: 16,
                  bottom: 16,
                  right: 48,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.fillFaint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  content,
                  style: textTheme.body.copyWith(color: colorScheme.textBase),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: GestureDetector(
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: content));
                    if (context.mounted) {
                      showShortToast(context, l10n.copied);
                    }
                  },
                  child: Icon(
                    Icons.copy_rounded,
                    size: 20,
                    color: colorScheme.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (isUrl) ...[
          ButtonWidgetV2(
            buttonType: ButtonTypeV2.primary,
            labelText: l10n.openLink,
            onTap: () async {
              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (_) {}
            },
          ),
          const SizedBox(height: 8),
          ButtonWidgetV2(
            buttonType: ButtonTypeV2.secondary,
            labelText: l10n.shareLink,
            shouldSurfaceExecutionStates: false,
            onTap: () async {
              await shareText(content, context: context);
            },
          ),
        ],
        if (isUpi)
          ButtonWidgetV2(
            buttonType: ButtonTypeV2.primary,
            labelText: l10n.pay,
            onTap: () async {
              try {
                final launched = await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                );
                if (!launched && context.mounted) {
                  showShortToast(context, l10n.noPaymentAppFound);
                }
              } catch (_) {
                if (context.mounted) {
                  showShortToast(context, l10n.noPaymentAppFound);
                }
              }
            },
          ),
        if (!isUrl && !isUpi)
          ButtonWidgetV2(
            buttonType: ButtonTypeV2.primary,
            labelText: l10n.shareLink,
            shouldSurfaceExecutionStates: false,
            onTap: () async {
              await shareText(content, context: context);
            },
          ),
      ],
    );
  }
}

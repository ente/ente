import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ente_auth/theme/colors.dart';
import 'package:ente_auth/theme/ente_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

class AuthQrDialog extends StatefulWidget {
  final String data;
  final String title;
  final String? subtitle;
  final String shareFileName;
  final String shareText;
  final String dialogTitle;
  final String shareButtonText;

  const AuthQrDialog({
    super.key,
    required this.data,
    required this.title,
    required this.shareFileName,
    required this.shareText,
    this.subtitle,
    this.dialogTitle = 'QR Code',
    this.shareButtonText = 'Share',
  });

  @override
  State<AuthQrDialog> createState() => _AuthQrDialogState();
}

class _AuthQrDialogState extends State<AuthQrDialog> {
  final GlobalKey _qrKey = GlobalKey();

  Future<void> _shareQrCode() async {
    try {
      if (!mounted) return;
      final boundary =
          _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) return;

      final Uint8List pngBytes = byteData.buffer.asUint8List();
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/${widget.shareFileName}');
      await file.writeAsBytes(pngBytes);

      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      final shareOrigin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : null;

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: widget.shareText,
          sharePositionOrigin: shareOrigin,
        ),
      );
    } catch (error) {
      debugPrint('Error sharing QR code: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final double qrSize = min(screenWidth - 80, 300.0);
    final enteTextTheme = getEnteTextTheme(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // QR text color - always black for scanability
    const qrTextColor = textBaseLight;

    final dialogBackgroundColor = isDark
        ? const Color(0xFF212121)
        : theme.colorScheme.surface;
    final closeBgColor = isDark
        ? const Color(0xFF292929)
        : const Color(0xFFF5F5F7);
    final closeIconColor = isDark ? theme.colorScheme.onSurface : qrTextColor;

    final dialogTitleStyle = theme.textTheme.titleLarge?.copyWith(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurface,
    );
    final shareButtonStyle = theme.textTheme.labelLarge?.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      shadowColor: isDark
          ? Colors.black.withValues(alpha: 0.7)
          : Colors.grey.withValues(alpha: 0.5),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Container(
          decoration: BoxDecoration(
            color: dialogBackgroundColor,
            borderRadius: BorderRadius.circular(24),
            border: isDark
                ? Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1,
                  )
                : null,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(widget.dialogTitle, style: dialogTitleStyle),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: closeBgColor,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(
                            Icons.close,
                            size: 20,
                            color: closeIconColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                RepaintBoundary(
                  key: _qrKey,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(color: qrBoxColor),
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          // Ente Auth icon at top right - positioned at corner
                          Positioned(
                            top: 2,
                            right: 2,
                            child: Transform.rotate(
                              angle: -4 * 3.14159 / 180, // -4 degrees
                              child: Image.asset(
                                'assets/qr_logo.png',
                                height: qrSize * 0.19,
                                width: qrSize * 0.19,
                              ),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.all(qrSize * 0.07),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                SizedBox(height: qrSize * 0.03),
                                // Issuer at top center
                                // Leave space for the logo (64px) + some padding
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: qrSize - 72,
                                  ),
                                  child: Text(
                                    widget.title,
                                    style: enteTextTheme.largeBold.copyWith(
                                      color: qrTextColor,
                                      fontSize: 20,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (widget.subtitle != null &&
                                    widget.subtitle!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: qrSize,
                                    ),
                                    child: Text(
                                      widget.subtitle!,
                                      style: enteTextTheme.small.copyWith(
                                        color: qrTextColor.withValues(
                                          alpha: 0.7,
                                        ),
                                        fontSize: 14,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                                SizedBox(height: qrSize * 0.07),

                                // QR Code with square style and purple corners
                                QrImageView(
                                  data: widget.data,
                                  eyeStyle: const QrEyeStyle(
                                    eyeShape: QrEyeShape.square,
                                    color: accentColor,
                                  ),
                                  dataModuleStyle: const QrDataModuleStyle(
                                    dataModuleShape: QrDataModuleShape.square,
                                    color: qrTextColor,
                                  ),
                                  version: QrVersions.auto,
                                  size: qrSize,
                                ),
                                SizedBox(height: qrSize * 0.07),
                                // Auth branding at bottom right
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: SvgPicture.asset(
                                    'assets/svg/app-logo.svg',
                                    height: 16,
                                    colorFilter: const ColorFilter.mode(
                                      accentColor,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: _shareQrCode,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      widget.shareButtonText,
                      textAlign: TextAlign.center,
                      style: shareButtonStyle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

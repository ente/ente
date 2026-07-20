import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:share_plus/share_plus.dart';

const Color _kDefaultQrBoxColor = Color(0xFFF5F5F7);
const Color _kDefaultQrTextColor = Color(0xFF1C1C1C);

sealed class QrBranding {
  const QrBranding();
}

class QrTextBranding extends QrBranding {
  final String text;
  final TextStyle style;

  const QrTextBranding({
    required this.text,
    this.style = const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
  });
}

class QrSvgBranding extends QrBranding {
  final String assetPath;
  final double height;

  const QrSvgBranding({required this.assetPath, this.height = 12});
}

class QrCodeDialog extends StatefulWidget {
  final String data;
  final String title;
  final String? subtitle;
  final Color accentColor;
  final QrBranding? branding;
  final String shareFileName;
  final String shareText;
  final int errorCorrectionLevel;
  final String dialogTitle;
  final String shareButtonText;
  final String? logoAssetPath;
  final PrettyQrDecoration? decoration;
  final Color? backgroundColor;
  final Color? qrCardColor;
  final Color? closeButtonBackgroundColor;
  final Color? closeButtonIconColor;
  final Color? shareButtonBackgroundColor;
  final EdgeInsets qrCardPadding;
  final double backgroundBorderRadius;
  final double cardBorderRadius;
  final double horizontalPadding;
  final double maxQrSize;
  final double minQrSize;
  final double titleMaxWidth;
  final double subtitleMaxWidth;
  final TextStyle? dialogTitleTextStyle;
  final TextStyle? titleTextStyle;
  final TextStyle? subtitleTextStyle;
  final TextStyle? shareButtonTextStyle;

  const QrCodeDialog({
    super.key,
    required this.data,
    required this.title,
    required this.accentColor,
    required this.shareFileName,
    required this.shareText,
    this.subtitle,
    this.branding,
    this.errorCorrectionLevel = QrErrorCorrectLevel.M,
    this.dialogTitle = 'QR Code',
    this.shareButtonText = 'Share',
    this.logoAssetPath,
    this.decoration,
    this.backgroundColor,
    this.qrCardColor,
    this.closeButtonBackgroundColor,
    this.closeButtonIconColor,
    this.shareButtonBackgroundColor,
    this.qrCardPadding = const EdgeInsets.all(20),
    this.backgroundBorderRadius = 24,
    this.cardBorderRadius = 22,
    this.horizontalPadding = 80,
    this.maxQrSize = 300,
    this.minQrSize = 150,
    this.titleMaxWidth = 224,
    this.subtitleMaxWidth = 176,
    this.dialogTitleTextStyle,
    this.titleTextStyle,
    this.subtitleTextStyle,
    this.shareButtonTextStyle,
  });

  @override
  State<QrCodeDialog> createState() => _QrCodeDialogState();
}

class _QrCodeDialogState extends State<QrCodeDialog> {
  final GlobalKey _qrKey = GlobalKey();

  Future<void> _shareQrCode() async {
    try {
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
      if (!mounted) {
        return;
      }

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

  PrettyQrDecoration _buildDefaultDecoration(Color finderColor) {
    return PrettyQrDecoration(
      shape: PrettyQrShape.custom(
        const PrettyQrDotsSymbol(
          color: _kDefaultQrTextColor,
          unifiedFinderPattern: false,
          unifiedAlignmentPatterns: false,
        ),
        finderPattern: PrettyQrSquaresSymbol(
          color: _kDefaultQrTextColor,
          rounding: 0.5,
          unifiedFinderPattern: true,
          finderPatternOuterThickness: 1.4,
          finderPatternOuterColor: finderColor,
          finderPatternInnerDotSize: 0.8,
          finderPatternInnerRounding: 1.0,
        ),
        alignmentPatterns: const PrettyQrSquaresSymbol(
          color: _kDefaultQrTextColor,
          rounding: 1.0,
        ),
      ),
      image: widget.logoAssetPath != null
          ? PrettyQrDecorationImage(
              image: AssetImage(widget.logoAssetPath!),
              scale: 0.25,
              padding: const EdgeInsets.all(24),
              position: PrettyQrDecorationImagePosition.embedded,
            )
          : null,
      background: Colors.transparent,
      quietZone: PrettyQrQuietZone.zero,
    );
  }

  Widget _buildBranding(QrBranding branding, Color color) {
    return switch (branding) {
      QrTextBranding(:final text, :final style) => Text(
        text,
        style: style.copyWith(color: style.color ?? color),
      ),
      QrSvgBranding(:final assetPath, :final height) => SvgPicture.asset(
        assetPath,
        height: height,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    final double qrSize = min(
      mediaQuery.size.width - widget.horizontalPadding,
      widget.maxQrSize,
    );
    final double qrCodeSize = max(qrSize - 100, widget.minQrSize);
    // Round to nearest even number for crisp rendering
    final double qrCodeSizeEven = (qrCodeSize / 2).round() * 2.0;

    final dialogBackgroundColor =
        widget.backgroundColor ??
        (isDark ? const Color(0xFF212121) : theme.colorScheme.surface);
    final cardColor = widget.qrCardColor ?? _kDefaultQrBoxColor;
    final closeBgColor =
        widget.closeButtonBackgroundColor ??
        (isDark ? const Color(0xFF292929) : const Color(0xFFF5F5F7));
    final closeIconColor =
        widget.closeButtonIconColor ??
        (isDark ? theme.colorScheme.onSurface : _kDefaultQrTextColor);
    final shareButtonColor =
        widget.shareButtonBackgroundColor ?? widget.accentColor;

    // Use theme text styles with copyWith for customization
    final titleStyle =
        widget.titleTextStyle ??
        textTheme.titleMedium?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
          color: _kDefaultQrTextColor,
        );
    final subtitleStyle =
        widget.subtitleTextStyle ??
        textTheme.bodySmall?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
          color: _kDefaultQrTextColor.withValues(alpha: 0.6),
        );
    final dialogTitleStyle =
        widget.dialogTitleTextStyle ??
        textTheme.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface,
        );
    final shareButtonStyle =
        widget.shareButtonTextStyle ??
        textTheme.labelLarge?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        );

    final decoration =
        widget.decoration ?? _buildDefaultDecoration(widget.accentColor);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(widget.backgroundBorderRadius),
      ),
      shadowColor: isDark
          ? Colors.black.withValues(alpha: 0.7)
          : Colors.grey.withValues(alpha: 0.5),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Container(
          decoration: BoxDecoration(
            color: dialogBackgroundColor,
            borderRadius: BorderRadius.circular(widget.backgroundBorderRadius),
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
                  child: Container(
                    width: double.infinity,
                    padding: widget.qrCardPadding,
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(
                        widget.cardBorderRadius,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: widget.titleMaxWidth,
                              child: Text(
                                widget.title,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: titleStyle,
                              ),
                            ),
                            if (widget.subtitle != null &&
                                widget.subtitle!.isNotEmpty)
                              SizedBox(
                                width: widget.subtitleMaxWidth,
                                child: Text(
                                  widget.subtitle!,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: subtitleStyle,
                                ),
                              ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: qrCodeSizeEven,
                              height: qrCodeSizeEven,
                              child: PrettyQrView(
                                qrImage: QrImage(
                                  QrCode.fromData(
                                    data: widget.data,
                                    errorCorrectLevel:
                                        widget.errorCorrectionLevel,
                                  ),
                                ),
                                decoration: decoration,
                              ),
                            ),
                            const SizedBox(height: 42),
                          ],
                        ),
                        if (widget.branding != null)
                          Positioned(
                            bottom: 0,
                            right: 2,
                            child: _buildBranding(
                              widget.branding!,
                              widget.accentColor,
                            ),
                          ),
                      ],
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
                      color: shareButtonColor,
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

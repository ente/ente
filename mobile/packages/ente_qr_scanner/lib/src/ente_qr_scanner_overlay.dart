import 'package:flutter/widgets.dart';

class EnteQrScannerOverlay {
  const EnteQrScannerOverlay({
    required this.borderColor,
    required this.overlayColor,
    this.cutOutSize = 260,
    this.borderRadius = 12,
    this.borderLength = 36,
    this.borderWidth = 4,
  });

  final Color borderColor;
  final Color overlayColor;
  final double cutOutSize;
  final double borderRadius;
  final double borderLength;
  final double borderWidth;

  Map<String, Object?> toCreationParams() {
    return {'cutOutSize': cutOutSize};
  }
}

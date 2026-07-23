import 'dart:async';
import 'dart:io';

import 'package:ente_qr_scanner/src/ente_qr_scanner_controller.dart';
import 'package:ente_qr_scanner/src/ente_qr_scanner_overlay.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _viewType = 'io.ente.qr_scanner/view';

class EnteQrScannerView extends StatefulWidget {
  const EnteQrScannerView({
    required this.overlay,
    required this.onScannerCreated,
    this.onError,
    super.key,
  });

  final EnteQrScannerOverlay overlay;
  final ValueChanged<EnteQrScannerController> onScannerCreated;
  final ValueChanged<String>? onError;

  @override
  State<EnteQrScannerView> createState() => _EnteQrScannerViewState();
}

class _EnteQrScannerViewState extends State<EnteQrScannerView> {
  EnteQrScannerController? _controller;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return const ColoredBox(color: Colors.black);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildPlatformView(),
        IgnorePointer(
          child: CustomPaint(painter: _QrScannerOverlayPainter(widget.overlay)),
        ),
      ],
    );
  }

  Widget _buildPlatformView() {
    final creationParams = widget.overlay.toCreationParams();
    if (Platform.isAndroid) {
      return AndroidView(
        viewType: _viewType,
        onPlatformViewCreated: _onPlatformViewCreated,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    return UiKitView(
      viewType: _viewType,
      onPlatformViewCreated: _onPlatformViewCreated,
      creationParams: creationParams,
      creationParamsCodec: const StandardMessageCodec(),
    );
  }

  void _onPlatformViewCreated(int platformViewId) {
    final controller = EnteQrScannerController(platformViewId);
    controller.onError = widget.onError;
    _controller = controller;
    widget.onScannerCreated(controller);
  }

  @override
  void dispose() {
    final controller = _controller;
    _controller = null;
    unawaited(controller?.dispose());
    super.dispose();
  }
}

class _QrScannerOverlayPainter extends CustomPainter {
  const _QrScannerOverlayPainter(this.overlay);

  final EnteQrScannerOverlay overlay;

  @override
  void paint(Canvas canvas, Size size) {
    final cutOutSize = overlay.cutOutSize
        .clamp(0.0, size.shortestSide)
        .toDouble();
    final cutOutRect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: cutOutSize,
      height: cutOutSize,
    );
    final cutOutRRect = RRect.fromRectAndRadius(
      cutOutRect,
      Radius.circular(overlay.borderRadius),
    );

    final overlayPath = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(cutOutRRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(overlayPath, Paint()..color = overlay.overlayColor);

    final borderPaint = Paint()
      ..color = overlay.borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = overlay.borderWidth
      ..strokeCap = StrokeCap.round;

    final radius = overlay.borderRadius;
    final length = overlay.borderLength;
    final left = cutOutRect.left;
    final right = cutOutRect.right;
    final top = cutOutRect.top;
    final bottom = cutOutRect.bottom;

    canvas
      ..drawLine(
        Offset(left + radius, top),
        Offset(left + length, top),
        borderPaint,
      )
      ..drawLine(
        Offset(left, top + radius),
        Offset(left, top + length),
        borderPaint,
      )
      ..drawLine(
        Offset(right - radius, top),
        Offset(right - length, top),
        borderPaint,
      )
      ..drawLine(
        Offset(right, top + radius),
        Offset(right, top + length),
        borderPaint,
      )
      ..drawLine(
        Offset(left + radius, bottom),
        Offset(left + length, bottom),
        borderPaint,
      )
      ..drawLine(
        Offset(left, bottom - radius),
        Offset(left, bottom - length),
        borderPaint,
      )
      ..drawLine(
        Offset(right - radius, bottom),
        Offset(right - length, bottom),
        borderPaint,
      )
      ..drawLine(
        Offset(right, bottom - radius),
        Offset(right, bottom - length),
        borderPaint,
      );
  }

  @override
  bool shouldRepaint(covariant _QrScannerOverlayPainter oldDelegate) {
    return oldDelegate.overlay != overlay;
  }
}

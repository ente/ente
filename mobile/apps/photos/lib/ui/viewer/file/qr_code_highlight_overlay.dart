import "package:ente_qr/ente_qr.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/viewer/file/qr_code_content_sheet.dart";

class QrCodeHighlightOverlay extends StatelessWidget {
  final List<QrDetection> detections;
  final EnteFile file;

  const QrCodeHighlightOverlay({
    required this.detections,
    required this.file,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (detections.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;

        double displayWidth;
        double displayHeight;
        if (file.hasDimensions) {
          final imageAspect = file.width / file.height;
          final screenAspect = screenWidth / screenHeight;
          if (imageAspect > screenAspect) {
            displayWidth = screenWidth;
            displayHeight = screenWidth / imageAspect;
          } else {
            displayHeight = screenHeight;
            displayWidth = screenHeight * imageAspect;
          }
        } else {
          displayWidth = screenWidth;
          displayHeight = screenHeight;
        }

        final offsetX = (screenWidth - displayWidth) / 2;
        final offsetY = (screenHeight - displayHeight) / 2;

        return SizedBox.expand(
          child: Stack(
            children: [
              for (final detection in detections)
                _QrTapRegion(
                  detection: detection,
                  offsetX: offsetX,
                  offsetY: offsetY,
                  displayWidth: displayWidth,
                  displayHeight: displayHeight,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _QrTapRegion extends StatefulWidget {
  final QrDetection detection;
  final double offsetX;
  final double offsetY;
  final double displayWidth;
  final double displayHeight;

  const _QrTapRegion({
    required this.detection,
    required this.offsetX,
    required this.offsetY,
    required this.displayWidth,
    required this.displayHeight,
  });

  @override
  State<_QrTapRegion> createState() => _QrTapRegionState();
}

class _QrTapRegionState extends State<_QrTapRegion> {
  Future<void> _onLongPress() async {
    await HapticFeedback.lightImpact();
    if (!mounted) return;
    await showQrCodeContentSheet(context, detections: [widget.detection]);
  }

  @override
  Widget build(BuildContext context) {
    final rawW = widget.detection.width * widget.displayWidth;
    final rawH = widget.detection.height * widget.displayHeight;
    const double minTapTarget = 48.0;
    final screenW = rawW < minTapTarget ? minTapTarget : rawW;
    final screenH = rawH < minTapTarget ? minTapTarget : rawH;
    final centerX =
        widget.offsetX +
        (widget.detection.x + widget.detection.width / 2) * widget.displayWidth;
    final centerY =
        widget.offsetY +
        (widget.detection.y + widget.detection.height / 2) *
            widget.displayHeight;

    return Positioned(
      left: centerX - screenW / 2,
      top: centerY - screenH / 2,
      width: screenW,
      height: screenH,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: _onLongPress,
        child: const SizedBox.expand(),
      ),
    );
  }
}

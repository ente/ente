import 'dart:typed_data';

import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:locker/services/scanner/scan_geometry.dart';
import 'package:locker/services/scanner/scan_session_controller.dart';
import 'package:locker/services/scanner/scanner_models.dart';

class ScannerCropPage extends StatefulWidget {
  const ScannerCropPage({
    super.key,
    required this.session,
    required this.pageId,
  });

  final ScanSessionController session;
  final String pageId;

  @override
  State<ScannerCropPage> createState() => _ScannerCropPageState();
}

class _ScannerCropPageState extends State<ScannerCropPage> {
  static const double _handleRadius = 22;

  static const double _minAreaFraction = 0.01;

  Uint8List? _sourceBytes;
  double _aspect = 3 / 4;
  List<Offset> _corners = const [];
  int _dragging = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final page = _page;
    if (page == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final bytes = await page.sourceJpeg.readAsBytes();
    if (!mounted) return;
    setState(() {
      _sourceBytes = bytes;
      _aspect = page.sourceWidth / page.sourceHeight;
      _corners = [...page.quad.corners];
    });
  }

  ScannedPage? get _page {
    for (final page in widget.session.pages) {
      if (page.id == widget.pageId) return page;
    }
    return null;
  }

  ScanQuad get _orderedQuad => orderClockwise(_corners);

  bool get _canSave =>
      _corners.length == 4 &&
      isUsableQuad(_orderedQuad.corners, minAreaFraction: _minAreaFraction);

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    final quad = _orderedQuad;
    await widget.session.updatePage(widget.pageId, quad: quad);
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final source = _sourceBytes;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.lg,
                vertical: Spacing.sm,
              ),
              child: Row(
                children: [
                  IconButtonComponent(
                    icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedCancel01,
                      color: colors.specialWhite,
                    ),
                    variant: IconButtonComponentVariant.unfilled,
                    onTap: () => Navigator.of(context).pop(),
                    tooltip: context.strings.cancel,
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        context.strings.adjustCrop,
                        style: TextStyles.body.copyWith(
                          color: colors.specialWhite,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox.square(dimension: 44),
                ],
              ),
            ),
            Expanded(
              child: source == null
                  ? Center(
                      child: CircularProgressIndicator(
                        color: colors.specialWhite,
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(Spacing.lg),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final container = Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          );
                          final rect = fittedRect(container, _aspect);

                          Offset toScreen(Offset normalized) => Offset(
                            rect.left + normalized.dx * rect.width,
                            rect.top + normalized.dy * rect.height,
                          );

                          Offset toNormalized(Offset screen) => Offset(
                            ((screen.dx - rect.left) / rect.width).clamp(
                              0.0,
                              1.0,
                            ),
                            ((screen.dy - rect.top) / rect.height).clamp(
                              0.0,
                              1.0,
                            ),
                          );

                          return GestureDetector(
                            onPanStart: (details) {
                              var best = -1;
                              var bestDistance = double.infinity;
                              for (var i = 0; i < _corners.length; i++) {
                                final distance =
                                    (toScreen(_corners[i]) -
                                            details.localPosition)
                                        .distance;
                                if (distance < bestDistance) {
                                  bestDistance = distance;
                                  best = i;
                                }
                              }
                              _dragging = bestDistance <= _handleRadius * 2
                                  ? best
                                  : -1;
                            },
                            onPanUpdate: (details) {
                              if (_dragging < 0) return;
                              setState(() {
                                _corners = [..._corners]
                                  ..[_dragging] = toNormalized(
                                    details.localPosition,
                                  );
                              });
                            },
                            onPanEnd: (_) => _dragging = -1,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Positioned.fromRect(
                                  rect: rect,
                                  child: Image.memory(source, fit: BoxFit.fill),
                                ),
                                CustomPaint(
                                  painter: _CropPainter(
                                    corners: [
                                      for (final c in _corners) toScreen(c),
                                    ],
                                    color: colors.primary,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(Spacing.xl),
              child: ButtonComponent(
                label: context.strings.save,
                onTap: source == null || !_canSave ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  const _CropPainter({required this.corners, required this.color});

  final List<Offset> corners;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) return;
    canvas.drawPath(
      Path()..addPolygon(corners, true),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    for (final corner in corners) {
      canvas.drawCircle(
        corner,
        12,
        Paint()..color = color.withValues(alpha: 0.45),
      );
      canvas.drawCircle(
        corner,
        12,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) =>
      oldDelegate.corners != corners || oldDelegate.color != color;
}

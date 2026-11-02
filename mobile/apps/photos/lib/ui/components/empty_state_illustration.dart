import "package:flutter/material.dart";
import "package:rive/rive.dart" as rive;

class EmptyStateIllustration extends StatefulWidget {
  const EmptyStateIllustration({
    required this.assetPath,
    required this.size,
    super.key,
  });

  final String assetPath;
  final Size size;

  @override
  State<EmptyStateIllustration> createState() => _EmptyStateIllustrationState();
}

class _EmptyStateIllustrationState extends State<EmptyStateIllustration> {
  rive.File? _file;
  rive.RiveWidgetController? _controller;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    rive.File? file;
    try {
      file = await rive.File.asset(
        widget.assetPath,
        riveFactory: rive.Factory.flutter,
      );
      if (file == null) return;
      if (!mounted) {
        file.dispose();
        return;
      }
      final controller = rive.RiveWidgetController(file)..advance(0);
      setState(() {
        _file = file;
        _controller = controller;
      });
    } catch (_) {
      file?.dispose();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _file?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return SizedBox(
      width: widget.size.width,
      height: widget.size.height,
      child: controller == null
          ? null
          : TickerMode(
              enabled: !MediaQuery.disableAnimationsOf(context),
              child: rive.RiveWidget(
                controller: controller,
                fit: rive.Fit.contain,
              ),
            ),
    );
  }
}

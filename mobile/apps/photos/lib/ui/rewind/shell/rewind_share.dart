import "dart:io";
import "dart:ui" as ui;

import "package:flutter/rendering.dart";
import "package:flutter/widgets.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:path_provider/path_provider.dart";
import "package:photos/ui/rewind/shell/rewind_page_scope.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:share_plus/share_plus.dart";

class RewindShareable extends StatefulWidget {
  const RewindShareable({
    required this.child,
    this.branded = true,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final bool branded;
  final bool enabled;

  @override
  State<RewindShareable> createState() => _RewindShareableState();
}

class _RewindShareableState extends State<RewindShareable> {
  late final _card = RewindShareCard(branded: widget.branded);
  RewindPageScope? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = RewindPageScope.maybeOf(context);
    if (scope?.page == _scope?.page && scope?.navigator == _scope?.navigator) {
      return;
    }
    _detach();
    _scope = scope;
    _attach();
  }

  @override
  void didUpdateWidget(RewindShareable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled) {
      widget.enabled ? _attach() : _detach();
    }
  }

  void _attach() {
    final scope = _scope;
    if (widget.enabled) scope?.navigator.attachShareCard(scope.page, _card);
  }

  void _detach() {
    final scope = _scope;
    scope?.navigator.detachShareCard(scope.page, _card);
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(key: _card.boundary, child: widget.child);
  }
}

Future<void> shareRewindCard(
  RewindShareCard card, {
  required double pixelRatio,
  required Rect wordmark,
  required Color wordmarkColor,
  Rect? origin,
}) async {
  final boundary = card.boundary.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary) return;
  var image = await boundary.toImage(pixelRatio: pixelRatio);
  if (card.branded) {
    final topLeft = boundary.globalToLocal(wordmark.topLeft);
    image = await _brand(
      image,
      topLeft & wordmark.size,
      wordmarkColor,
      pixelRatio,
    );
  }
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) throw StateError("Could not encode the Rewind card");
  final directory = await getTemporaryDirectory();
  final file = File(
    "${directory.path}/ente-rewind-${DateTime.now().millisecondsSinceEpoch}.png",
  );
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: "image/png")],
      sharePositionOrigin: origin,
    ),
  );
}

Future<ui.Image> _brand(
  ui.Image image,
  Rect wordmark,
  Color color,
  double pixelRatio,
) async {
  final svg = await vg.loadPicture(
    SvgFileLoader(RewindAssets.file(RewindAssets.wordmark)),
    null,
  );
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
    ..drawImage(image, Offset.zero, Paint())
    ..scale(pixelRatio)
    ..translate(wordmark.left, wordmark.top)
    ..scale(wordmark.width / svg.size.width)
    ..saveLayer(
      Offset.zero & svg.size,
      Paint()..colorFilter = ColorFilter.mode(color, BlendMode.srcIn),
    )
    ..drawPicture(svg.picture)
    ..restore();
  svg.picture.dispose();
  final picture = recorder.endRecording();
  final branded = await picture.toImage(image.width, image.height);
  picture.dispose();
  image.dispose();
  return branded;
}

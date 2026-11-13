import "package:flutter/foundation.dart";
import "package:flutter/material.dart";

const fileViewerFilmstripPreviewKey = ValueKey<String>(
  "file-viewer-filmstrip-preview",
);

typedef FileViewerFilmstripPreviewBuilder =
    Widget Function(BuildContext context, int index);

class FileViewerFilmstripPreviewLayer extends StatelessWidget {
  final ValueListenable<int?> previewIndex;
  final FileViewerFilmstripPreviewBuilder itemBuilder;

  const FileViewerFilmstripPreviewLayer({
    required this.previewIndex,
    required this.itemBuilder,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: previewIndex,
      builder: (context, index, _) {
        if (index == null) return const SizedBox.shrink();
        final preview = itemBuilder(context, index);
        return Positioned.fill(
          child: AbsorbPointer(
            child: ColoredBox(
              key: fileViewerFilmstripPreviewKey,
              color: Colors.black,
              child: preview,
            ),
          ),
        );
      },
    );
  }
}

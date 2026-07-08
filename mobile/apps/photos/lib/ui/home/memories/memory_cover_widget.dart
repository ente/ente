import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:photos/core/constants.dart";
import "package:photos/models/memories/smart_memory.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/home/memories/all_memories_page.dart";
import "package:photos/ui/home/memories/memory_cover_util.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";

class MemoryCoverWidget extends StatefulWidget {
  final SmartMemory smartMemory;
  final List<SmartMemory> allMemories;
  final double height;
  final double width;
  static const defaultWidth = 145.011;
  static const defaultHeight = 210.5;
  static const outerStrokeWidth = 1.0;
  static const aspectRatio = defaultHeight / defaultWidth;
  static const gap = 5.0;
  final int currentMemoryIndex;

  const MemoryCoverWidget({
    required this.smartMemory,
    required this.allMemories,
    required this.height,
    required this.width,
    required this.currentMemoryIndex,
    super.key,
  });

  @override
  State<MemoryCoverWidget> createState() => _MemoryCoverWidgetState();
}

class _MemoryCoverWidgetState extends State<MemoryCoverWidget> {
  @override
  Widget build(BuildContext context) {
    //memories will be empty if all memories are deleted and setState is called
    //after FullScreenMemory screen is popped
    final memories = widget.smartMemory.memories;
    if (memories.isEmpty) {
      return const SizedBox.shrink();
    }

    final index = getNextMemoryIndex(memories);
    final title = widget.smartMemory.title;

    final memory = memories[index];
    final isSeen = memory.isSeen();
    final titleFontWeight =
        widget.smartMemory.type == MemoryType.time ||
            widget.smartMemory.type == MemoryType.filler
        ? FontWeight.w300
        : FontWeight.w700;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MemoryCoverWidget.gap / 2.0,
      ),
      child: GestureDetector(
        onTap: () async {
          await routeToPage(
            context,
            forceCustomPageRoute: true,
            AllMemoriesPage(
              initialPageIndex: widget.currentMemoryIndex,
              allMemories: widget.allMemories,
            ),
          );
          if (!mounted) return;
          setState(() {});
        },
        child: Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Container(
              foregroundDecoration: isSeen
                  ? const BoxDecoration(
                      color: Color(0xFFBFBFBF),
                      backgroundBlendMode: BlendMode.saturation,
                    )
                  : null,
              child: Stack(
                fit: StackFit.expand,
                alignment: Alignment.bottomCenter,
                children: [
                  Hero(
                    tag: "memories" + memory.file.tag,
                    child: ThumbnailWidget(
                      memory.file,
                      shouldShowSyncStatus: false,
                      thumbnailSize: thumbnailLargeSize,
                      key: Key("memories" + memory.file.tag),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withValues(alpha: 0.5),
                          Colors.transparent,
                        ],
                        stops: const [0, 1],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    child: SizedBox(
                      width: widget.width,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Hero(
                          tag: title,
                          child: Text(
                            title,
                            style: getEnteTextTheme(context).body.copyWith(
                              fontSize: widget.height * 0.085,
                              fontFamily: TextStyles.outfitFontFamily,
                              package: TextStyles.fontPackage,
                              color: isSeen ? textFaintDark : Colors.white,
                              fontWeight: titleFontWeight,
                            ),
                            textAlign: TextAlign.left,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

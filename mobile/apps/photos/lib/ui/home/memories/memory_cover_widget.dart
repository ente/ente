import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/effects.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/home/memories/all_memories_page.dart";
import "package:photos/ui/home/memories/memory_cover_util.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";

// TODO: Use a single instance variable for `allMemories` and `allTitles`
class MemoryCoverWidget extends StatefulWidget {
  final List<Memory> memories;
  final List<List<Memory>> allMemories;
  final double height;
  final double width;
  static const outerStrokeWidth = 1.0;
  static const aspectRatio = 236.924 / 163.214;
  static const gap = 5.0;
  final String title;
  final List<String> allTitle;
  final int currentMemoryIndex;

  const MemoryCoverWidget({
    required this.memories,
    required this.allMemories,
    required this.height,
    required this.width,
    required this.title,
    required this.allTitle,
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
    if (widget.memories.isEmpty) {
      return const SizedBox.shrink();
    }

    final index = getNextMemoryIndex(widget.memories);
    final title = widget.title;

    final memory = widget.memories[index];
    final isSeen = memory.isSeen();
    final brightness = Theme.of(context).brightness;

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
              allTitles: widget.allTitle,
            ),
          );
          if (!mounted) return;
          setState(() {});
        },
        child: Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            boxShadow: brightness == Brightness.dark
                ? [
                    const BoxShadow(
                      color: strokeFainterDark,
                      spreadRadius: MemoryCoverWidget.outerStrokeWidth,
                      blurRadius: 0,
                    ),
                  ]
                : [...shadowFloatFaintestLight],
            borderRadius: BorderRadius.circular(22),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
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
                              fontSize: widget.height * 0.095,
                              fontFamily: TextStyles.outfitFontFamily,
                              package: TextStyles.fontPackage,
                              color: isSeen ? textFaintDark : Colors.white,
                              fontWeight: .w400,
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

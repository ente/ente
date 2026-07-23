import 'package:flutter/material.dart';
import "package:photos/models/memories/smart_memory.dart";
import "package:photos/theme/colors.dart";
import "package:photos/ui/home/memories/full_screen_memory.dart";
import "package:photos/ui/home/memories/memory_cover_util.dart";

class AllMemoriesPage extends StatefulWidget {
  final int initialPageIndex;
  final int inititalFileIndex;
  final List<SmartMemory> allMemories;
  final bool isFromWidgetOrNotifications;

  const AllMemoriesPage({
    super.key,
    required this.allMemories,
    required this.initialPageIndex,
    this.inititalFileIndex = 0,
    this.isFromWidgetOrNotifications = false,
  });

  @override
  State<AllMemoriesPage> createState() => _AllMemoriesPageState();
}

class _AllMemoriesPageState extends State<AllMemoriesPage>
    with SingleTickerProviderStateMixin {
  late PageController pageController;
  bool isFirstLoad = true;

  @override
  void initState() {
    super.initState();
    pageController = PageController(initialPage: widget.initialPageIndex);
  }

  @override
  void dispose() {
    pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: backgroundColorDark,
      child: PageView.builder(
        controller: pageController,
        physics: const BouncingScrollPhysics(),
        hitTestBehavior: HitTestBehavior.translucent,
        itemCount: widget.allMemories.length,
        itemBuilder: (context, index) {
          final smartMemory = widget.allMemories[index];
          final initialMemoryIndex =
              widget.isFromWidgetOrNotifications && isFirstLoad
              ? widget.inititalFileIndex
              : getNextMemoryIndex(smartMemory.memories);
          isFirstLoad = false;
          return FullScreenMemoryDataUpdater(
            initialIndex: initialMemoryIndex,
            memories: smartMemory.memories,
            child: FullScreenMemory(
              smartMemory.title,
              initialMemoryIndex,
              onNextMemory: index < widget.allMemories.length - 1
                  ? () => pageController.nextPage(
                      duration: const Duration(milliseconds: 675),
                      curve: Curves.easeOutQuart,
                    )
                  : null,
              onPreviousMemory: index > 0
                  ? () => pageController.previousPage(
                      duration: const Duration(milliseconds: 675),
                      curve: Curves.easeOutQuart,
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }
}

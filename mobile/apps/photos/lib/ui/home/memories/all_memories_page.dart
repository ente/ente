import 'package:flutter/material.dart';
import "package:photos/core/event_bus.dart";
import "package:photos/events/pause_video_event.dart";
import "package:photos/models/memories/smart_memory.dart";
import "package:photos/service_locator.dart";
import "package:photos/theme/colors.dart";
import "package:photos/ui/home/memories/full_screen_memory.dart";
import "package:photos/ui/home/memories/memory_cover_util.dart";
import "package:photos/ui/home/memories/memory_music_session.dart";

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
  late final List<SmartMemory> _memories;
  late final int _initialPageIndex;
  late int _activePageIndex;

  @override
  void initState() {
    super.initState();
    final initialMemory = widget.allMemories[widget.initialPageIndex];
    _memories = widget.allMemories
        .where((memory) => memory.memories.isNotEmpty)
        .toList();
    _initialPageIndex = _memories.indexOf(initialMemory);
    _activePageIndex = _initialPageIndex;
    pageController = PageController(initialPage: _initialPageIndex);
  }

  @override
  void dispose() {
    pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = Container(
      width: double.infinity,
      height: double.infinity,
      color: backgroundColorDark,
      child: PageView.builder(
        controller: pageController,
        physics: const BouncingScrollPhysics(),
        hitTestBehavior: HitTestBehavior.translucent,
        itemCount: _memories.length,
        onPageChanged: (index) {
          Bus.instance.fire(PauseVideoEvent());
          setState(() => _activePageIndex = index);
        },
        itemBuilder: (context, index) {
          final smartMemory = _memories[index];
          final initialMemoryIndex = _initialItemIndexForPage(index);
          return FullScreenMemoryDataUpdater(
            initialIndex: initialMemoryIndex,
            memories: smartMemory.memories,
            child: FullScreenMemory(
              smartMemory.title,
              initialMemoryIndex,
              memoryID: smartMemory.id,
              isActive: index == _activePageIndex,
              onNextMemory: index < _memories.length - 1
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
    return flagService.internalUser
        ? MemoryMusicSession(
            memoryIDs: _memories.map((memory) => memory.id).toList(),
            child: page,
          )
        : page;
  }

  int _initialItemIndexForPage(int pageIndex) {
    final memories = _memories[pageIndex].memories;
    return widget.isFromWidgetOrNotifications && pageIndex == _initialPageIndex
        ? widget.inititalFileIndex
        : getNextMemoryIndex(memories);
  }
}

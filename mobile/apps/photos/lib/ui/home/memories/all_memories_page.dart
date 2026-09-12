import "package:ente_pure_utils/ente_pure_utils.dart";
import 'package:flutter/material.dart';
import "package:photos/core/event_bus.dart";
import "package:photos/events/pause_video_event.dart";
import "package:photos/models/memories/smart_memory.dart";
import "package:photos/models/memory_lane/memory_lane_models.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/app_navigation_service.dart";
import "package:photos/theme/colors.dart";
import "package:photos/ui/home/memories/full_screen_memory.dart";
import "package:photos/ui/home/memories/memory_cover_util.dart";
import "package:photos/ui/home/memories/memory_music_session.dart";
import "package:photos/ui/viewer/people/memory_lane_page_v2.dart";

Future<void> openAllMemoriesPage({
  required List<SmartMemory> allMemories,
  required int initialPageIndex,
  MemoryLanePersonTimeline? memoryLane,
  PersonEntity? memoryLanePerson,
  BuildContext? context,
  int initialFileIndex = 0,
  bool isFromWidgetOrNotifications = false,
}) async {
  final page = AllMemoriesPage(
    allMemories: allMemories,
    memoryLane: memoryLane,
    memoryLanePerson: memoryLanePerson,
    initialPageIndex: initialPageIndex,
    initialFileIndex: initialFileIndex,
    isFromWidgetOrNotifications: isFromWidgetOrNotifications,
  );
  if (context != null) {
    await routeToPage(context, page, forceCustomPageRoute: true);
    return;
  }
  await AppNavigationService.instance.pushPage(
    page,
    forceCustomPageRoute: true,
  );
}

class MemoryPageWrapper {
  final String id;
  final Widget Function({
    VoidCallback? onNextMemory,
    VoidCallback? onPreviousMemory,
  })
  widget;

  const MemoryPageWrapper({required this.id, required this.widget});
}

class AllMemoriesPage extends StatefulWidget {
  final int initialPageIndex;
  final int initialFileIndex;
  final List<SmartMemory> allMemories;
  final MemoryLanePersonTimeline? memoryLane;
  final PersonEntity? memoryLanePerson;
  final bool isFromWidgetOrNotifications;

  const AllMemoriesPage({
    super.key,
    required this.allMemories,
    required this.initialPageIndex,
    this.memoryLane,
    this.memoryLanePerson,
    this.initialFileIndex = 0,
    this.isFromWidgetOrNotifications = false,
  });

  @override
  State<AllMemoriesPage> createState() => _AllMemoriesPageState();
}

class _AllMemoriesPageState extends State<AllMemoriesPage> {
  late final PageController _pageController;
  late final List<MemoryPageWrapper> _pages;
  late int _activePageIndex;
  bool _isMediaInteractionLocked = false;

  @override
  void initState() {
    super.initState();
    final initialMemoryIndex =
        widget.initialPageIndex - (widget.memoryLane == null ? 0 : 1);
    final initialMemory = initialMemoryIndex < 0
        ? null
        : widget.allMemories[initialMemoryIndex];
    _pages = _buildPages();
    _activePageIndex = _pages.indexWhere(
      (page) =>
          page.id ==
          (initialMemory == null
              ? "memoryLane_${widget.memoryLane!.personId}"
              : initialMemory.id),
    );
    _pageController = PageController(initialPage: _activePageIndex);
  }

  List<MemoryPageWrapper> _buildPages() {
    final memoryLane = widget.memoryLane;
    final hasSeenMemoryLane =
        memoryLane != null &&
        localSettings.hasSeenMemoryLane(memoryLane.personId);
    final pages = <MemoryPageWrapper>[];
    for (final smartMemory in widget.allMemories) {
      if (smartMemory.memories.isEmpty) continue;
      final index =
          pages.length + (memoryLane != null && !hasSeenMemoryLane ? 1 : 0);
      pages.add(
        MemoryPageWrapper(
          id: smartMemory.id,
          widget: ({onNextMemory, onPreviousMemory}) {
            final initialMemoryIndex =
                widget.isFromWidgetOrNotifications &&
                    index == _pageController.initialPage
                ? widget.initialFileIndex
                : getNextMemoryIndex(smartMemory.memories);
            return FullScreenMemoryDataUpdater(
              key: ValueKey(smartMemory.id),
              initialIndex: initialMemoryIndex,
              memories: smartMemory.memories,
              child: FullScreenMemory(
                smartMemory.title,
                initialMemoryIndex,
                memoryID: smartMemory.id,
                isActive: index == _activePageIndex,
                onMediaInteractionLockChanged: (isLocked) {
                  if (index != _activePageIndex ||
                      _isMediaInteractionLocked == isLocked) {
                    return;
                  }
                  setState(() => _isMediaInteractionLocked = isLocked);
                },
                onNextMemory: onNextMemory,
                onPreviousMemory: onPreviousMemory,
              ),
            );
          },
        ),
      );
    }
    if (memoryLane != null) {
      pages.insert(
        hasSeenMemoryLane ? pages.length : 0,
        MemoryPageWrapper(
          id: "memoryLane_${memoryLane.personId}",
          widget: ({onNextMemory, onPreviousMemory}) => MemoryLanePageV2(
            key: ValueKey("memoryLane_${memoryLane.personId}"),
            personId: memoryLane.personId,
            isCluster: memoryLane.isCluster,
            person: widget.memoryLanePerson,
            isActive:
                _pages[_activePageIndex].id ==
                "memoryLane_${memoryLane.personId}",
            onNextMemory: onNextMemory,
            onPreviousMemory: onPreviousMemory,
          ),
        ),
      );
    }
    return pages;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MemoryMusicSession(
      memoryIDs: _pages.map((page) => page.id).toList(),
      child: ColoredBox(
        color: backgroundColorDark,
        child: PageView.builder(
          controller: _pageController,
          physics: _isMediaInteractionLocked
              ? const NeverScrollableScrollPhysics()
              : const BouncingScrollPhysics(),
          hitTestBehavior: HitTestBehavior.translucent,
          itemCount: _pages.length,
          onPageChanged: (index) {
            Bus.instance.fire(PauseVideoEvent());
            setState(() {
              _activePageIndex = index;
              _isMediaInteractionLocked = false;
            });
          },
          itemBuilder: (context, index) => _pages[index].widget(
            onNextMemory: index < _pages.length - 1
                ? () => _pageController.nextPage(
                    duration: const Duration(milliseconds: 675),
                    curve: Curves.easeOutQuart,
                  )
                : null,
            onPreviousMemory: index > 0
                ? () => _pageController.previousPage(
                    duration: const Duration(milliseconds: 675),
                    curve: Curves.easeOutQuart,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

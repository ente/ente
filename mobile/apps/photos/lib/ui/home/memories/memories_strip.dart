import "dart:async";
import "dart:math";

import 'package:flutter/material.dart';
import "package:flutter_animate/flutter_animate.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/memories_changed_event.dart";
import "package:photos/events/memories_setting_changed.dart";
import "package:photos/events/memory_seen_event.dart";
import "package:photos/models/memories/smart_memory.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/notification_service.dart";
import "package:photos/ui/home/memories/crafting_memories_card.dart";
import 'package:photos/ui/home/memories/memory_card.dart';
import "package:photos/ui/home/memories/memory_cover_util.dart";
import "package:photos/ui/home/memories/memory_video_prefetcher.dart";

class MemoriesStripWidget extends StatefulWidget {
  const MemoriesStripWidget({super.key});

  @override
  State<MemoriesStripWidget> createState() => _MemoriesStripWidgetState();
}

class _MemoriesStripWidgetState extends State<MemoriesStripWidget> {
  late StreamSubscription<MemoriesSettingChanged> _memoriesSettingSubscription;
  late StreamSubscription<MemoriesChangedEvent> _memoriesChangedSubscription;
  late StreamSubscription<MemorySeenEvent> _memorySeenSubscription;
  late double _memoryheight;
  late double _memoryWidth;

  // Delay cover warming past startup; generations invalidate stale work.
  Timer? _warmTimer;
  int _warmGeneration = 0;
  String? _lastWarmSignature;
  final _videoPrefetcher = MemoryVideoPrefetcher();
  late Future<bool> _showCraftingMemories;

  @override
  void initState() {
    super.initState();
    _refreshShowCraftingMemories();
    _memoriesSettingSubscription = Bus.instance
        .on<MemoriesSettingChanged>()
        .listen((event) {
          if (mounted) {
            setState(() {});
          }
        });
    _memoriesChangedSubscription = Bus.instance
        .on<MemoriesChangedEvent>()
        .listen((event) {
          if (mounted) {
            setState(() {});
          }
        });
    _memorySeenSubscription = Bus.instance.on<MemorySeenEvent>().listen((
      event,
    ) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _refreshShowCraftingMemories() {
    _showCraftingMemories = _getShowCraftingMemories();
  }

  Future<bool> _getShowCraftingMemories() async {
    final hasPermissions = await NotificationService.instance
        .hasGrantedPermissions();
    if (hasPermissions) return false;
    final hasDismissed = await localSettings
        .getCraftingMemoriesBannerDismissed();
    if (hasDismissed) return false;
    return true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    if (screenWidth < screenHeight) {
      _memoryWidth = min(
        screenWidth * (MemoryCardWidget.defaultWidth / 376.0),
        MemoryCardWidget.defaultWidth * 1.5,
      );
      _memoryheight = _memoryWidth * MemoryCardWidget.aspectRatio;
    } else {
      _memoryWidth = min(
        screenHeight * .3,
        MemoryCardWidget.defaultWidth * 1.5,
      );
      _memoryheight = _memoryWidth * MemoryCardWidget.aspectRatio;
    }
  }

  @override
  void dispose() {
    _memoriesSettingSubscription.cancel();
    _memoriesChangedSubscription.cancel();
    _memorySeenSubscription.cancel();
    _warmTimer?.cancel();
    _videoPrefetcher.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!memoriesCacheService.showAnyMemories) {
      _cancelPendingWarm();
      return const SizedBox.shrink();
    }
    return _memories();
  }

  Widget _memories() {
    return FutureBuilder<List<SmartMemory>>(
      initialData: memoriesCacheService.currentMemoriesSync,
      future: memoriesCacheService.getMemories(),
      builder: (context, snapshot) {
        if (snapshot.hasError || !snapshot.hasData) {
          _cancelPendingWarm();
          return const SizedBox.shrink();
        }
        if (snapshot.data!.isEmpty) {
          _cancelPendingWarm();
          return const SizedBox.shrink();
        }
        final orderedMemories = _orderForStrip(snapshot.data!);
        _scheduleWarmCovers(orderedMemories);
        return Column(
          key: ValueKey(identityHashCode(snapshot.data)),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            _buildMemories(orderedMemories),
            const SizedBox(height: 10),
          ],
        ).animate().fadeIn(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOutCirc,
        );
      },
    );
  }

  // Keep prefetch and UI on the same unseen-first ordering.
  List<SmartMemory> _orderForStrip(List<SmartMemory> memories) {
    final List<SmartMemory> orderedMemories = [];
    final List<SmartMemory> seen = [];
    for (final memory in memories) {
      final allSeen = memory.memories.every((element) => element.isSeen());
      if (allSeen) {
        seen.add(memory);
      } else {
        orderedMemories.add(memory);
      }
    }
    orderedMemories.addAll(seen);
    return orderedMemories;
  }

  void _scheduleWarmCovers(List<SmartMemory> memories) {
    final warmSignature = _warmSignature(memories);
    if (warmSignature == _lastWarmSignature) return;
    _lastWarmSignature = warmSignature;
    _warmGeneration++;
    final gen = _warmGeneration;
    _warmTimer?.cancel();
    _warmTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || gen != _warmGeneration) return;
      final memoryLists = memories
          .map((e) => e.memories)
          .toList(growable: false);
      _videoPrefetcher.prefetchFiles(
        memoryLists
            .take(kMemoryCoverWarmCap)
            .where((memories) => memories.isNotEmpty)
            .map((memories) => memories[getNextMemoryIndex(memories)].file),
        stillActive: () => mounted && gen == _warmGeneration,
        replacePending: true,
      );
      unawaited(
        warmMemoryCovers(
          memoryLists,
          stillActive: () => mounted && gen == _warmGeneration,
        ),
      );
    });
  }

  String _warmSignature(List<SmartMemory> memories) {
    return memories
        .map((e) => e.memories)
        .take(kMemoryCoverWarmCap)
        .where((memories) => memories.isNotEmpty)
        .map((memories) {
          final file = memories[getNextMemoryIndex(memories)].file;
          return '${file.uploadedFileID ?? ""}|'
              '${file.generatedID ?? ""}|'
              '${file.localID ?? ""}|'
              '${file.fileType.name}';
        })
        .join(',');
  }

  // Invalidate in-flight work and allow the same dataset to be scheduled again.
  void _cancelPendingWarm() {
    _warmTimer?.cancel();
    _warmTimer = null;
    _warmGeneration++;
    _lastWarmSignature = null;
    _videoPrefetcher.clearPending();
  }

  Widget _buildMemories(List<SmartMemory> memories) {
    return FutureBuilder<bool>(
      future: _showCraftingMemories,
      builder: (context, snapshot) {
        final showCraftingMemories = snapshot.data ?? false;
        return SizedBox(
          height: _memoryheight + MemoryCardWidget.outerStrokeWidth * 2,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(
              horizontal: MemoryCardWidget.gap / 2.0,
            ),
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            scrollDirection: Axis.horizontal,
            itemCount: (showCraftingMemories ? 1 : 0) + memories.length,
            itemBuilder: (context, itemIndex) {
              if (showCraftingMemories && itemIndex == 0) {
                return CraftingMemoriesCardWidget(
                  width: _memoryheight * 0.5,
                  height: _memoryheight,
                  onNotificationsPermissionGranted: () {
                    if (!mounted) return;
                    setState(() {
                      _refreshShowCraftingMemories();
                    });
                  },
                );
              }
              final memoryIndex = itemIndex - (showCraftingMemories ? 1 : 0);
              return MemoryCardWidget(
                smartMemory: memories[memoryIndex],
                allMemories: memories,
                height: _memoryheight,
                width: _memoryWidth,
                currentMemoryIndex: memoryIndex,
              );
            },
          ),
        );
      },
    );
  }
}

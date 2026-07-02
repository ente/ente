import "dart:async";
import "dart:math";

import 'package:flutter/material.dart';
import "package:flutter_animate/flutter_animate.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/memories_changed_event.dart";
import "package:photos/events/memories_setting_changed.dart";
import "package:photos/events/memory_seen_event.dart";
import 'package:photos/models/memories/memory.dart';
import "package:photos/models/memories/smart_memory.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/home/memories/memory_cover_util.dart";
import 'package:photos/ui/home/memories/memory_cover_widget.dart';
import "package:photos/ui/home/memories/memory_video_prefetcher.dart";

class MemoriesWidget extends StatefulWidget {
  const MemoriesWidget({super.key});

  @override
  State<MemoriesWidget> createState() => _MemoriesWidgetState();
}

class _MemoriesWidgetState extends State<MemoriesWidget> {
  late StreamSubscription<MemoriesSettingChanged> _memoriesSettingSubscription;
  late StreamSubscription<MemoriesChangedEvent> _memoriesChangedSubscription;
  late StreamSubscription<MemorySeenEvent> _memorySeenSubscription;
  late double _memoryheight;
  late double _memoryWidth;

  // Cover-warming: delay the first pass so we don't contend with home-screen
  // first-frame work, and restart whenever a new memory set arrives. The
  // generation counter makes any stale timer's eventual fire a no-op.
  Timer? _warmTimer;
  int _warmGeneration = 0;
  String? _lastWarmSignature;
  final _videoPrefetcher = MemoryVideoPrefetcher();

  @override
  void initState() {
    super.initState();
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    if (screenWidth < screenHeight) {
      _memoryWidth = min(screenWidth * .4352, 240);
      _memoryheight = _memoryWidth * MemoryCoverWidget.aspectRatio;
    } else {
      _memoryWidth = min(screenHeight * .35, 240);
      _memoryheight = _memoryWidth * MemoryCoverWidget.aspectRatio;
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
        final collated = _collateForStrip(snapshot.data!);
        _scheduleWarmCovers(collated);
        return Column(
          key: ValueKey(identityHashCode(snapshot.data)),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            _buildMemories(collated),
            const SizedBox(height: 10),
          ],
        ).animate().fadeIn(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOutCirc,
        );
      },
    );
  }

  // Groups the memories into the order the strip renders: unseen first, then
  // seen. Shared between the prefetch pass and the UI so they agree on which
  // memory occupies each visual slot.
  List<(List<Memory>, String)> _collateForStrip(List<SmartMemory> memories) {
    final List<(List<Memory>, String)> collated = [];
    final List<SmartMemory> seen = [];
    for (final memory in memories) {
      final allSeen = memory.memories.every((element) => element.isSeen());
      if (allSeen) {
        seen.add(memory);
      } else {
        collated.add((memory.memories, memory.title));
      }
    }
    collated.addAll(seen.map((e) => (e.memories, e.title)));
    return collated;
  }

  void _scheduleWarmCovers(List<(List<Memory>, String)> collated) {
    final warmSignature = _warmSignature(collated);
    if (warmSignature == _lastWarmSignature) return;
    _lastWarmSignature = warmSignature;
    _warmGeneration++;
    final gen = _warmGeneration;
    _warmTimer?.cancel();
    _warmTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || gen != _warmGeneration) return;
      final memoryLists = collated.map((e) => e.$1).toList(growable: false);
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

  String _warmSignature(List<(List<Memory>, String)> collated) {
    return collated
        .map((e) => e.$1)
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

  // Kill any pending or in-flight warm pass: cancels the delay timer, bumps
  // the generation so a running warmMemoryCovers loop exits at its next
  // stillActive check, clears pending video work, and clears the last-warmed
  // marker so a subsequent dataset re-schedules even if it's the same
  // reference as before.
  void _cancelPendingWarm() {
    _warmTimer?.cancel();
    _warmTimer = null;
    _warmGeneration++;
    _lastWarmSignature = null;
    _videoPrefetcher.clearPending();
  }

  Widget _buildMemories(List<(List<Memory>, String)> collated) {
    return SizedBox(
      height: _memoryheight + MemoryCoverWidget.outerStrokeWidth * 2,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(
          horizontal: MemoryCoverWidget.gap / 2.0,
        ),
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        scrollDirection: Axis.horizontal,
        itemCount: collated.length,
        itemBuilder: (context, itemIndex) {
          return MemoryCoverWidget(
            memories: collated[itemIndex].$1,
            allMemories: collated.map((e) => e.$1).toList(),
            height: _memoryheight,
            width: _memoryWidth,
            title: collated[itemIndex].$2,
            allTitle: collated.map((e) => e.$2).toList(),
            currentMemoryIndex: itemIndex,
          );
        },
      ),
    );
  }
}

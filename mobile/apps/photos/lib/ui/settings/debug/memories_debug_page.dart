import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file_load_result.dart";
import "package:photos/models/memories/clip_memory.dart";
import "package:photos/models/memories/filler_memory.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/memories/people_memory.dart";
import "package:photos/models/memories/smart_memory.dart";
import "package:photos/models/memories/time_memory.dart";
import "package:photos/models/memories/trip_memory.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/service_locator.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";

class MemoriesDebugPage extends StatefulWidget {
  const MemoriesDebugPage({super.key});

  @override
  State<MemoriesDebugPage> createState() => _MemoriesDebugPageState();
}

class _MemoriesDebugLoadResult {
  final List<SmartMemory> memories;
  final DateTime calculationTime;
  final Duration duration;

  const _MemoriesDebugLoadResult({
    required this.memories,
    required this.calculationTime,
    required this.duration,
  });
}

class _MemoriesDebugPageState extends State<MemoriesDebugPage> {
  static const List<MemoryType> _typeOrder = [
    MemoryType.onThisDay,
    MemoryType.people,
    MemoryType.trips,
    MemoryType.clip,
    MemoryType.time,
    MemoryType.filler,
  ];

  late DateTime _calculationTime;
  late Future<_MemoriesDebugLoadResult> _loadFuture;
  final Set<MemoryType> _expandedTypes = {};

  @override
  void initState() {
    super.initState();
    _calculationTime = DateTime.now();
    _loadFuture = _loadMemories();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    return Scaffold(
      backgroundColor: colorScheme.backgroundColour,
      appBar: AppBar(
        backgroundColor: colorScheme.backgroundColour,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text("Memories Debug", style: textTheme.largeBold),
        actions: [
          IconButton(
            tooltip: "Change calculation date",
            onPressed: _pickCalculationDate,
            icon: const Icon(Icons.calendar_today_outlined),
          ),
          IconButton(
            tooltip: "Recompute",
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<_MemoriesDebugLoadResult>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      "Computing all memories for debug view…",
                      style: textTheme.smallMuted,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 28,
                      color: colorScheme.warning500,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Failed to compute memories",
                      style: textTheme.smallBold,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "${snapshot.error}",
                      style: textTheme.miniMuted,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _reload,
                      child: const Text("Retry"),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = snapshot.data!;
          final groupedMemories = _groupMemories(data.memories);
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _SummaryCard(
                totalMemories: data.memories.length,
                calculationTime: data.calculationTime,
                duration: data.duration,
                groupedMemories: groupedMemories,
                typeLabelBuilder: _memoryTypeLabel,
              ),
              const SizedBox(height: 16),
              if (data.memories.isEmpty)
                _EmptyState(calculationTime: data.calculationTime)
              else
                ...groupedMemories.entries.expand((entry) {
                  final isExpanded = _expandedTypes.contains(entry.key);
                  return [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _MemoryDebugSectionHeader(
                        title: _memoryTypeLabel(entry.key),
                        count: entry.key == MemoryType.trips
                            ? entry.value
                                  .whereType<TripMemory>()
                                  .where(
                                    (m) =>
                                        m.locationName == null ||
                                        !m.locationName!.toLowerCase().contains(
                                          "base",
                                        ),
                                  )
                                  .length
                            : entry.value.length,
                        icon: _memoryTypeIcon(entry.key),
                        isExpanded: isExpanded,
                        onTap: () => _toggleSection(entry.key),
                      ),
                    ),
                    if (isExpanded)
                      ...entry.value.map(
                        (memory) => Padding(
                          padding: const EdgeInsets.only(
                            left: 8,
                            right: 8,
                            bottom: 8,
                          ),
                          child: _MemoryDebugTile(
                            memory: memory,
                            onTap: () => _openMemory(memory),
                            icon: _memoryTypeIcon(memory.type),
                            subtitle: _buildSubtitle(memory),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                  ];
                }),
            ],
          );
        },
      ),
    );
  }

  Future<_MemoriesDebugLoadResult> _loadMemories() async {
    final stopwatch = Stopwatch()..start();
    final calculationTime = _calculationTime;
    final memories = await memoriesCacheService.debugGetAllMemories(
      calcTime: calculationTime,
    );
    stopwatch.stop();
    return _MemoriesDebugLoadResult(
      memories: memories,
      calculationTime: calculationTime,
      duration: stopwatch.elapsed,
    );
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _expandedTypes.clear();
      _loadFuture = _loadMemories();
    });
  }

  Future<void> _pickCalculationDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _calculationTime,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _expandedTypes.clear();
      _calculationTime = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _calculationTime.hour,
        _calculationTime.minute,
        _calculationTime.second,
        _calculationTime.millisecond,
        _calculationTime.microsecond,
      );
      _loadFuture = _loadMemories();
    });
  }

  void _toggleSection(MemoryType type) {
    setState(() {
      if (_expandedTypes.contains(type)) {
        _expandedTypes.remove(type);
      } else {
        _expandedTypes.add(type);
      }
    });
  }

  Map<MemoryType, List<SmartMemory>> _groupMemories(
    List<SmartMemory> memories,
  ) {
    final grouped = <MemoryType, List<SmartMemory>>{};
    for (final type in _typeOrder) {
      grouped[type] = <SmartMemory>[];
    }
    for (final memory in memories) {
      grouped.putIfAbsent(memory.type, () => <SmartMemory>[]).add(memory);
    }
    grouped.removeWhere((_, values) => values.isEmpty);
    return grouped;
  }

  Future<void> _openMemory(SmartMemory memory) async {
    final files = Memory.filesFromMemories(memory.memories);
    if (files.isEmpty) return;
    await routeToPage(
      context,
      _MemoryGalleryPage(title: memory.title, files: files),
      forceCustomPageRoute: true,
    );
  }

  String _buildSubtitle(SmartMemory memory) {
    final summaryParts = <String>[
      _buildTypeSpecificSummary(memory),
      "${memory.memories.length} photos",
    ].where((part) => part.isNotEmpty).toList();
    final details = <String>[
      summaryParts.join(" • "),
      _formatCaptureRange(memory),
    ].where((part) => part.isNotEmpty).toList();
    return details.join("\n");
  }

  String _buildTypeSpecificSummary(SmartMemory memory) {
    switch (memory) {
      case PeopleMemory():
        final parts = <String>[
          _enumLabel(memory.peopleMemoryType.name),
          if (memory.personName != null && memory.personName!.isNotEmpty)
            memory.personName!
          else if (memory.isUnnamedCluster)
            "Unnamed cluster",
        ];
        return parts.join(" • ");
      case TripMemory():
        return memory.locationName ??
            (memory.tripYear != null ? memory.tripYear!.toString() : "");
      case ClipMemory():
        return _enumLabel(memory.clipMemoryType.name);
      case TimeMemory():
        if (memory.day != null) {
          return DateFormat.MMMd().format(memory.day!);
        }
        if (memory.month != null) {
          return DateFormat.MMMM().format(memory.month!);
        }
        if (memory.yearsAgo != null) {
          return "${memory.yearsAgo} years ago";
        }
        return "";
      case FillerMemory():
        return "${memory.yearsAgo} years ago";
      default:
        return "";
    }
  }

  String _formatCaptureRange(SmartMemory memory) {
    final creationTimes = memory.memories
        .map((memory) => memory.file.creationTime)
        .whereType<int>()
        .toList();
    if (creationTimes.isEmpty) {
      return "No capture dates";
    }
    creationTimes.sort();
    final formatter = DateFormat.yMMMd();
    final first = formatter.format(
      DateTime.fromMicrosecondsSinceEpoch(creationTimes.first),
    );
    final last = formatter.format(
      DateTime.fromMicrosecondsSinceEpoch(creationTimes.last),
    );
    if (first == last) {
      return "Captured: $first";
    }
    return "Captured: $first - $last";
  }

  String _memoryTypeLabel(MemoryType type) {
    switch (type) {
      case MemoryType.onThisDay:
        return "On This Day";
      case MemoryType.people:
        return "People";
      case MemoryType.trips:
        return "Trips";
      case MemoryType.clip:
        return "CLIP";
      case MemoryType.time:
        return "Time";
      case MemoryType.filler:
        return "Filler";
    }
  }

  IconData _memoryTypeIcon(MemoryType type) {
    switch (type) {
      case MemoryType.onThisDay:
        return Icons.today_outlined;
      case MemoryType.people:
        return Icons.people_outline;
      case MemoryType.trips:
        return Icons.map_outlined;
      case MemoryType.clip:
        return Icons.auto_awesome_outlined;
      case MemoryType.time:
        return Icons.schedule_outlined;
      case MemoryType.filler:
        return Icons.history_outlined;
    }
  }

  String _enumLabel(String value) {
    final words = value.replaceAllMapped(
      RegExp(r"([A-Z])"),
      (match) => " ${match.group(1)}",
    );
    if (words.isEmpty) return value;
    return words[0].toUpperCase() + words.substring(1);
  }
}

class _SummaryCard extends StatelessWidget {
  final int totalMemories;
  final DateTime calculationTime;
  final Duration duration;
  final Map<MemoryType, List<SmartMemory>> groupedMemories;
  final String Function(MemoryType type) typeLabelBuilder;

  const _SummaryCard({
    required this.totalMemories,
    required this.calculationTime,
    required this.duration,
    required this.groupedMemories,
    required this.typeLabelBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final formattedDate = DateFormat.yMMMd().add_jm().format(calculationTime);
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.backgroundElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.strokeMuted.withValues(alpha: 0.4),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$totalMemories memories", style: textTheme.largeBold),
          const SizedBox(height: 4),
          Text(
            "Calculated for $formattedDate in ${duration.inMilliseconds} ms",
            style: textTheme.smallMuted,
          ),
          if (groupedMemories.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: groupedMemories.entries
                  .map(
                    (entry) => Container(
                      decoration: BoxDecoration(
                        color: colorScheme.fillFaint,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        "${typeLabelBuilder(entry.key)} ${entry.key == MemoryType.trips ? entry.value.whereType<TripMemory>().where((m) => m.locationName == null || !m.locationName!.toLowerCase().contains("base")).length : entry.value.length}",
                        style: textTheme.mini,
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }
}

class _MemoryDebugSectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;
  final bool isExpanded;
  final VoidCallback onTap;

  const _MemoryDebugSectionHeader({
    required this.title,
    required this.count,
    required this.icon,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: colorScheme.backgroundElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.strokeMuted.withValues(alpha: 0.32),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colorScheme.fillFaint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 20, color: colorScheme.strokeBase),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text("$title ($count)", style: textTheme.smallBold),
                ),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.expand_more, color: colorScheme.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MemoryDebugTile extends StatelessWidget {
  final SmartMemory memory;
  final VoidCallback onTap;
  final IconData icon;
  final String subtitle;

  const _MemoryDebugTile({
    required this.memory,
    required this.onTap,
    required this.icon,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final firstFile = memory.memories.isNotEmpty
        ? memory.memories.first.file
        : null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: colorScheme.backgroundElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.strokeMuted.withValues(alpha: 0.32),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: firstFile != null
                        ? ThumbnailWidget(firstFile, rawThumbnail: true)
                        : Container(
                            color: colorScheme.fillFaint,
                            child: Icon(
                              icon,
                              size: 20,
                              color: colorScheme.strokeBase,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(memory.title, style: textTheme.smallBold),
                      const SizedBox(height: 6),
                      Text(subtitle, style: textTheme.miniMuted),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.chevron_right_outlined,
                  color: colorScheme.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final DateTime calculationTime;

  const _EmptyState({required this.calculationTime});

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    final formattedDate = DateFormat.yMMMd().add_jm().format(calculationTime);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        children: [
          Text(
            "No memories were produced for $formattedDate.",
            style: textTheme.smallMuted,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _MemoryGalleryPage extends StatefulWidget {
  final String title;
  final List<EnteFile> files;

  const _MemoryGalleryPage({required this.title, required this.files});

  @override
  State<_MemoryGalleryPage> createState() => _MemoryGalleryPageState();
}

class _MemoryGalleryPageState extends State<_MemoryGalleryPage> {
  late final SelectedFiles _selectedFiles;

  @override
  void initState() {
    super.initState();
    _selectedFiles = SelectedFiles();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    return GalleryFilesState(
      child: Scaffold(
        backgroundColor: colorScheme.backgroundColour,
        appBar: AppBar(
          backgroundColor: colorScheme.backgroundColour,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Text(widget.title, style: textTheme.largeBold),
        ),
        body: Gallery(
          asyncLoader: (creationStartTime, creationEndTime, {limit, asc}) {
            final result = widget.files
                .where(
                  (file) =>
                      file.creationTime! >= creationStartTime &&
                      file.creationTime! <= creationEndTime,
                )
                .toList();
            return Future.value(
              FileLoadResult(result, result.length < widget.files.length),
            );
          },
          tagPrefix: "memory_debug_gallery",
          selectedFiles: _selectedFiles,
          initialFiles: widget.files,
        ),
      ),
    );
  }
}

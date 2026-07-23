import "dart:async";

import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/memory_lane_changed_event.dart";
import "package:photos/models/memory_lane/memory_lane_models.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/memory_lane/memory_lane_cache_service.dart";
import "package:photos/services/memory_lane/memory_lane_service.dart";
import "package:photos/theme/ente_theme.dart";

class MemoryLaneDebugPanel extends StatefulWidget {
  final PersonEntity person;

  const MemoryLaneDebugPanel({required this.person, super.key});

  @override
  State<MemoryLaneDebugPanel> createState() => _MemoryLaneDebugPanelState();
}

class _MemoryLaneDebugPanelState extends State<MemoryLaneDebugPanel> {
  MemoryLanePersonTimeline? _timeline;
  bool _loading = false;
  String? _error;
  String? _info;
  StreamSubscription<MemoryLaneChangedEvent>? _timelineSubscription;

  bool get _featureEnabled => flagService.facesTimeline;

  @override
  void initState() {
    super.initState();
    if (kDebugMode && _featureEnabled) {
      _reloadTimeline();
      _timelineSubscription = Bus.instance.on<MemoryLaneChangedEvent>().listen(
        _handleTimelineChanged,
      );
    }
  }

  @override
  void dispose() {
    _timelineSubscription?.cancel();
    super.dispose();
  }

  void _handleTimelineChanged(MemoryLaneChangedEvent event) {
    if (event.personId != widget.person.remoteID) return;
    _reloadTimeline();
  }

  Future<void> _reloadTimeline() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final timeline = await MemoryLaneService.instance.getTimeline(
        widget.person.remoteID,
      );
      if (!mounted) return;
      setState(() {
        _timeline = timeline;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = "$error";
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _forceRecompute() async {
    MemoryLaneService.instance.schedulePersonRecompute(
      widget.person.remoteID,
      force: true,
      trigger: "debug_panel",
    );
    if (!mounted) return;
    setState(() {
      _info =
          "Recompute queued at ${DateTime.now().toLocal().toIso8601String()}";
    });
  }

  Future<void> _clearTimeline() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await MemoryLaneCacheService.instance.removeTimeline(
        widget.person.remoteID,
      );
      await _reloadTimeline();
      if (!mounted) return;
      setState(() {
        _info =
            "Timeline cache cleared at ${DateTime.now().toLocal().toIso8601String()}";
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = "$error";
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode || !_featureEnabled) return const SizedBox.shrink();
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final timeline = _timeline;
    final bool inReadySet = MemoryLaneService.instance.hasReadyTimelineSync(
      widget.person.remoteID,
    );
    final DateTime? updatedAt = timeline == null
        ? null
        : DateTime.fromMicrosecondsSinceEpoch(
            timeline.updatedAtMicros,
          ).toLocal();
    final int uniqueYears = timeline == null
        ? 0
        : timeline.entries.map((entry) => entry.year).toSet().length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.fillFaint,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.strokeFaint),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bug_report_outlined, color: colorScheme.primary500),
                const SizedBox(width: 8),
                Text("Faces timeline debug", style: textTheme.bodyBold),
                const Spacer(),
                IconButton(
                  onPressed: _loading ? null : _reloadTimeline,
                  tooltip: "Refresh timeline",
                  icon: _loading
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.primary500,
                          ),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Text(
                _error!,
                style: textTheme.miniMuted.copyWith(
                  color: colorScheme.warning500,
                ),
              ),
            if (_info != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _info!,
                  style: textTheme.miniMuted.copyWith(
                    color: colorScheme.primary500,
                  ),
                ),
              ),
            Text(
              "Status: ${timeline == null ? "missing" : timeline.status.name}",
              style: textTheme.miniMuted,
            ),
            Text(
              "Ready set contains person: ${inReadySet ? "yes" : "no"}",
              style: textTheme.miniMuted,
            ),
            Text(
              "Entries: ${timeline?.entries.length ?? 0} • Years: $uniqueYears",
              style: textTheme.miniMuted,
            ),
            Text(
              "Updated: ${updatedAt?.toIso8601String() ?? "n/a"}",
              style: textTheme.miniMuted,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _loading ? null : _forceRecompute,
                  child: const Text("Force recompute"),
                ),
                FilledButton.tonal(
                  onPressed: _loading || timeline == null
                      ? null
                      : _clearTimeline,
                  child: const Text("Clear cache entry"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

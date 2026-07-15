import "dart:async";

import "package:flutter/material.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/events/sync_status_update_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/services/sync/remote_sync_service.dart";
import "package:photos/services/sync/sync_service.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/viewer/gallery/empty_state.dart";

class SyncAwareEmptyState extends StatefulWidget {
  @visibleForTesting
  static const recheckInterval = Duration(seconds: 3);

  final Widget child;

  @visibleForTesting
  final ValueGetter<bool>? isSyncInProgress;

  const SyncAwareEmptyState({
    this.child = const EmptyState(),
    this.isSyncInProgress,
    super.key,
  });

  @override
  State<SyncAwareEmptyState> createState() => _SyncAwareEmptyStateState();
}

class _SyncAwareEmptyStateState extends State<SyncAwareEmptyState> {
  late final StreamSubscription<SyncStatusUpdate> _syncStatusSubscription;
  late final Timer _recheckTimer;
  late bool _isSyncInProgress;

  @override
  void initState() {
    super.initState();
    _isSyncInProgress = _readSyncState();
    _syncStatusSubscription = Bus.instance.on<SyncStatusUpdate>().listen((_) {
      _refreshSyncState();
    });
    _recheckTimer = Timer.periodic(
      SyncAwareEmptyState.recheckInterval,
      (_) => _refreshSyncState(),
    );
  }

  @override
  void dispose() {
    _recheckTimer.cancel();
    _syncStatusSubscription.cancel();
    super.dispose();
  }

  bool _readSyncState() {
    return widget.isSyncInProgress?.call() ??
        (SyncService.instance.isSyncInProgress() ||
            RemoteSyncService.instance.isNonSilentSyncInProgress());
  }

  void _refreshSyncState() {
    if (!mounted) return;
    final isSyncInProgress = _readSyncState();
    if (_isSyncInProgress != isSyncInProgress) {
      setState(() {
        _isSyncInProgress = isSyncInProgress;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSyncInProgress) {
      return widget.child;
    }

    final textColor = Theme.of(
      context,
    ).colorScheme.defaultTextColor.withValues(alpha: 0.35);
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(dimension: 24, child: EnteLoadingWidget()),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              AppLocalizations.of(context).syncing,
              style: TextStyle(color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}

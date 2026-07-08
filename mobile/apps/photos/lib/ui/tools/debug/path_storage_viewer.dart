import 'dart:io';

import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import "package:photos/generated/l10n.dart";
import 'package:photos/theme/ente_theme.dart';
import 'package:photos/ui/components/captioned_text_widget.dart';
import 'package:photos/ui/components/menu_item_widget/menu_item_widget.dart';
import "package:photos/ui/settings/pending_sync/pending_sync_info_screen.dart";

class PathStorageItem {
  final String path;
  final String title;
  final bool allowCacheClear;

  PathStorageItem.name(this.path, this.title, {this.allowCacheClear = false});
}

class PathStorageViewer extends StatefulWidget {
  final PathStorageItem item;
  final bool removeTopRadius;
  final bool removeBottomRadius;
  final bool enableDoubleTapClear;

  const PathStorageViewer(
    this.item, {
    this.removeTopRadius = false,
    this.removeBottomRadius = false,
    this.enableDoubleTapClear = false,
    super.key,
  });

  @override
  State<PathStorageViewer> createState() => _PathStorageViewerState();
}

class _PathStorageViewerState extends State<PathStorageViewer> {
  final Logger _logger = Logger((_PathStorageViewerState).toString());
  late Future<DirectoryStat> _statFuture;

  @override
  void initState() {
    super.initState();
    _statFuture = getDirectoryStat(Directory(widget.item.path));
  }

  @override
  void didUpdateWidget(PathStorageViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refresh the future when the widget updates (key changes)
    if (oldWidget.item.path != widget.item.path ||
        oldWidget.key != widget.key) {
      _statFuture = getDirectoryStat(Directory(widget.item.path));
    }
  }

  void _safeRefresh() async {
    if (mounted) {
      setState(() {
        _statFuture = getDirectoryStat(Directory(widget.item.path));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DirectoryStat>(
      future: _statFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return _buildMenuItemWidget(snapshot.data, null);
        } else if (snapshot.hasError) {
          _logger.severe(
            "Failed to get state for ${widget.item.title}",
            snapshot.error,
          );
          return _buildMenuItemWidget(null, snapshot.error);
        } else {
          return _buildMenuItemWidget(null, null);
        }
      },
    );
  }

  Widget _buildMenuItemWidget(DirectoryStat? stat, Object? err) {
    return MenuItemWidget(
      key: UniqueKey(),
      alignCaptionedTextToLeft: true,
      captionedTextWidget: CaptionedTextWidget(
        title: widget.item.title,
        subTitle: stat != null ? '${stat.fileCount}' : null,
        subTitleColor: getEnteColorScheme(context).textFaint,
      ),
      trailingWidget: stat != null
          ? Padding(
              padding: const EdgeInsets.only(left: 12.0),
              child: Text(
                formatBytes(stat.size),
                style: getEnteTextTheme(
                  context,
                ).small.copyWith(color: getEnteColorScheme(context).textFaint),
              ),
            )
          : SizedBox.fromSize(
              size: const Size.square(14),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: getEnteColorScheme(context).strokeMuted,
              ),
            ),
      trailingIcon: err != null ? Icons.error_outline_outlined : null,
      trailingIconIsMuted: err != null,
      singleBorderRadius: 8,
      menuItemColor: getEnteColorScheme(context).fillFaint,
      isBottomBorderRadiusRemoved: widget.removeBottomRadius,
      isTopBorderRadiusRemoved: widget.removeTopRadius,
      showOnlyLoadingState: true,
      onTap: () async {
        if (kDebugMode) {
          await Clipboard.setData(ClipboardData(text: widget.item.path));
          _logger.info(widget.item.path);
        }
      },
      onDoubleTap: () async {
        if (widget.item.allowCacheClear && widget.enableDoubleTapClear) {
          await deleteDirectoryContents(widget.item.path);
          _safeRefresh();
        }
      },
      onLongPress: () async {
        if (widget.item.title == AppLocalizations.of(context).pendingSync) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const PendingSyncInfoScreen(),
            ),
          );
        }
      },
    );
  }
}

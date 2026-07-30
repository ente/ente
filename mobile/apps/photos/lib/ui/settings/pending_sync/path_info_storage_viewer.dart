import 'dart:io';

import 'package:ente_components/ente_components.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

class PathInfoStorageItem {
  final String path;
  final String title;
  final bool allowCacheClear;
  final String match;

  PathInfoStorageItem.name(
    this.path,
    this.title,
    this.match, {
    this.allowCacheClear = false,
  });
}

class PathInfoStorageViewer extends StatefulWidget {
  final PathInfoStorageItem item;
  final bool enableDoubleTapClear;

  const PathInfoStorageViewer(
    this.item, {
    this.enableDoubleTapClear = false,
    super.key,
  });

  @override
  State<PathInfoStorageViewer> createState() => _PathInfoStorageViewerState();
}

class _PathInfoStorageViewerState extends State<PathInfoStorageViewer> {
  final Logger _logger = Logger((_PathInfoStorageViewerState).toString());

  @override
  void initState() {
    super.initState();
  }

  void _safeRefresh() async {
    if (mounted) {
      setState(() => {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DirectoryStat>(
      future: getDirectoryStat(
        Directory(widget.item.path),
        prefix: widget.item.match,
      ),
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
    final colors = context.componentColors;
    return MenuComponent(
      key: UniqueKey(),
      title: widget.item.title,
      subtitle: stat != null ? '${stat.fileCount}' : null,
      trailing: err != null
          ? Icon(Icons.error_outline_outlined, color: colors.textLight)
          : stat != null
          ? Padding(
              padding: const EdgeInsets.only(left: 12.0),
              child: Text(
                formatBytes(stat.size),
                style: TextStyles.mini.copyWith(color: colors.textLight),
              ),
            )
          : SizedBox.fromSize(
              size: const Size.square(14),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.strokeFaint,
              ),
            ),
      onTap: () async {
        if (kDebugMode) {
          await Clipboard.setData(ClipboardData(text: widget.item.path));
          debugPrint(widget.item.path);
        }
      },
      onDoubleTap: () async {
        if (widget.item.allowCacheClear && widget.enableDoubleTapClear) {
          await deleteDirectoryContents(widget.item.path);
          _safeRefresh();
        }
      },
    );
  }
}

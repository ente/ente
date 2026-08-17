import 'package:flutter/material.dart';
import 'package:log_viewer/src/core/log_store.dart';
import 'package:log_viewer/src/ui/log_viewer_page.dart';
import 'package:logging/logging.dart' as log;

export 'src/core/log_database.dart';
export 'src/core/log_models.dart';
export 'src/core/log_store.dart';
export 'src/ui/log_detail_page.dart';
export 'src/ui/log_filter_dialog.dart';
export 'src/ui/log_list_tile.dart';
export 'src/ui/log_viewer_page.dart';

class LogViewer {
  static bool _initialized = false;
  static String _prefix = '';

  static Future<void> initialize({String prefix = ''}) async {
    if (_initialized) return;

    _prefix = prefix;

    await LogStore.instance.initialize();

    _registerWithSuperLogging();

    _initialized = true;
  }

  static void _registerWithSuperLogging() {
    try {
      log.Logger.root.onRecord.listen((record) {
        LogStore.addLogRecord(record, _prefix);
      });
    } catch (e) {
      log.Logger.root.onRecord.listen((record) {
        LogStore.addLogRecord(record, '');
      });
    }
  }

  static Widget getViewerPage() {
    if (!_initialized) {
      throw StateError(
        'LogViewer not initialized. Call LogViewer.initialize() first.',
      );
    }
    return const LogViewerPage();
  }

  static Future<void> openViewer(BuildContext context) async {
    if (!_initialized) {
      await initialize();
    }
    if (!context.mounted) {
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LogViewerPage()),
    );
  }

  static bool get isInitialized => _initialized;

  static Future<void> dispose() async {
    if (_initialized) {
      await LogStore.instance.dispose();
      _initialized = false;
    }
  }
}

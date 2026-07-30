import 'package:flutter/material.dart';
import 'package:log_viewer/src/core/log_store.dart';
import 'package:log_viewer/src/ui/log_viewer_page.dart';
import 'package:logging/logging.dart' as log;

export 'src/core/log_database.dart';
export 'src/core/log_models.dart';
// Core exports
export 'src/core/log_store.dart';
export 'src/ui/log_detail_page.dart';
export 'src/ui/log_filter_dialog.dart';
export 'src/ui/log_list_tile.dart';
// UI exports
export 'src/ui/log_viewer_page.dart';

/// Main entry point for the log viewer functionality
class LogViewer {
  static bool _initialized = false;
  static String _prefix = '';

  /// Initialize the log viewer
  /// This should be called once during app startup
  static Future<void> initialize({String prefix = ''}) async {
    if (_initialized) return;

    _prefix = prefix;

    // Initialize the log store
    await LogStore.instance.initialize();

    // Register callback with super_logging if available
    _registerWithSuperLogging();

    _initialized = true;
  }

  /// Register callback with super_logging to receive logs
  static void _registerWithSuperLogging() {
    // Try to register with SuperLogging if available
    try {
      // This will be called dynamically by the main app if SuperLogging is available
      // For now, fallback to direct logger listening without prefix
      log.Logger.root.onRecord.listen((record) {
        LogStore.addLogRecord(record, _prefix);
      });
    } catch (e) {
      // SuperLogging not available, fallback to direct logger
      log.Logger.root.onRecord.listen((record) {
        LogStore.addLogRecord(record, '');
      });
    }
  }

  /// Get the log viewer page widget
  static Widget getViewerPage() {
    if (!_initialized) {
      throw StateError(
        'LogViewer not initialized. Call LogViewer.initialize() first.',
      );
    }
    return const LogViewerPage();
  }

  /// Open the log viewer in a new route
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

  /// Check if log viewer is initialized
  static bool get isInitialized => _initialized;

  /// Dispose of log viewer resources
  static Future<void> dispose() async {
    if (_initialized) {
      await LogStore.instance.dispose();
      _initialized = false;
    }
  }
}

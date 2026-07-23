# Log Viewer Integration Examples

This document provides examples of integrating the log_viewer package into your Flutter application, both as a standalone solution and integrated with SuperLogging.

## Standalone Integration (Without SuperLogging)

### Basic Setup

```dart
import 'package:flutter/material.dart';
import 'package:log_viewer/log_viewer.dart';
import 'package:logging/logging.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the log viewer
  await LogViewer.initialize();

  // Set up logging
  Logger.root.level = Level.ALL;

  // Log viewer automatically captures all logs - no manual setup needed!

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Log Viewer Example',
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final Logger _logger = Logger('MyHomePage');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Log Viewer Example'),
        actions: [
          IconButton(
            icon: Icon(Icons.bug_report),
            onPressed: () {
              // Navigate to log viewer
              LogViewer.openViewer(context);
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                _logger.info('Info log message');
              },
              child: Text('Log Info'),
            ),
            ElevatedButton(
              onPressed: () {
                _logger.warning('Warning log message');
              },
              child: Text('Log Warning'),
            ),
            ElevatedButton(
              onPressed: () {
                try {
                  throw Exception('Test error');
                } catch (e, s) {
                  _logger.severe('Error occurred', e, s);
                }
              },
              child: Text('Log Error'),
            ),
          ],
        ),
      ),
    );
  }
}
```

## SuperLogging Integration (Ente Photos Style)

### Complete Integration Example

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:log_viewer/log_viewer.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

// SuperLogging-like configuration
class LogConfig {
  final String? logDirPath;
  final int maxLogFiles;
  final bool enableInDebugMode;
  final FutureOrVoidCallback? body;
  final String prefix;

  LogConfig({
    this.logDirPath,
    this.maxLogFiles = 10,
    this.enableInDebugMode = false,
    this.body,
    this.prefix = "",
  });
}

class SuperLogging {
  static final Logger _logger = Logger('SuperLogging');
  static late LogConfig config;

  static Future<void> main([LogConfig? appConfig]) async {
    appConfig ??= LogConfig();
    SuperLogging.config = appConfig;

    WidgetsFlutterBinding.ensureInitialized();

    // Initialize log viewer in debug mode with prefix
    if (kDebugMode) {
      try {
        await LogViewer.initialize(prefix: appConfig.prefix);
        _logger.info("Log viewer initialized successfully");
      } catch (e) {
        _logger.warning("Failed to initialize log viewer: $e");
      }
    }

    Logger.root.level = kDebugMode ? Level.ALL : Level.INFO;
    Logger.root.onRecord.listen(onLogRecord);

    if (appConfig.body != null) {
      await appConfig.body!();
    }
  }

  static Future<void> onLogRecord(LogRecord rec) async {
    final str = "${config.prefix} ${rec.toString()}";

    // Print to console
    if (kDebugMode) {
      print(str);
    }

    // Log viewer automatically captures all logs - no manual integration needed!
  }
}

// Main application with SuperLogging integration
Future<void> main() async {
  await SuperLogging.main(
    LogConfig(
      body: () async {
        runApp(MyApp());
      },
      logDirPath: (await getApplicationSupportDirectory()).path + "/logs",
      maxLogFiles: 5,
      enableInDebugMode: true,
      prefix: "[APP]",
    ),
  );
}
```

### Ente Photos Integration Example

In your Ente Photos app's main.dart or SuperLogging class, add the log viewer initialization:

```dart
Future runWithLogs(Function() function, {String prefix = ""}) async {
  await SuperLogging.main(
    LogConfig(
      body: function,
      logDirPath: (await getApplicationSupportDirectory()).path + "/logs",
      maxLogFiles: 5,
      sentryDsn: kDebugMode ? sentryDebugDSN : sentryDSN,
      tunnel: sentryTunnel,
      enableInDebugMode: true,
      prefix: prefix,
    ),
  );
}

// In SuperLogging.main():
if (kDebugMode) {
  try {
    // Simply initialize with prefix - no callbacks needed!
    await LogViewer.initialize(prefix: appConfig.prefix);
    _logger.info("Log viewer initialized successfully");
  } catch (e) {
    _logger.warning("Failed to initialize log viewer: $e");
  }
}
```

### Settings Page Integration

Add log viewer access in your settings page (debug mode only):

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:log_viewer/log_viewer.dart';

class SettingsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Existing email/user info with debug button
          Row(
            children: [
              Expanded(
                child: Text(
                  'user@example.com',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              if (kDebugMode)
                GestureDetector(
                  onTap: () {
                    LogViewer.openViewer(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.bug_report,
                      size: 20,
                      color: Colors.grey,
                    ),
                  ),
                ),
            ],
          ),
          // Other settings items...
        ],
      ),
    );
  }
}
```

## Features Available

Once integrated, users will have access to:

1. **Real-time log viewing** - Logs appear as they're generated
2. **Filtering by log level** - Show only errors, warnings, info, etc.
3. **Filtering by logger name** - Focus on specific components
4. **Text search** - Search within log messages and errors
5. **Date range filtering** - View logs from specific time periods
6. **Export functionality** - Share logs as text files
7. **Detailed view** - Tap any log to see full details including stack traces

## How It Works

1. The `log_viewer` package automatically registers with `Logger.root.onRecord` on initialization
2. Logs are stored in a local SQLite database (auto-truncated to 10000 entries by default)
3. The UI provides filtering and search capabilities
4. When a prefix is provided, it's automatically prepended to all log messages
5. No manual callback registration or integration needed - just initialize and go!

## Troubleshooting

If logs aren't appearing:

1. Ensure `LogViewer.initialize()` is called early in app initialization
2. Check that the app has write permissions for the database
3. Verify that `Logger.root.level` is set appropriately (not OFF)
4. If using a prefix, verify it's being passed correctly to `LogViewer.initialize(prefix: yourPrefix)`

## Performance Notes

- Logs are buffered and batch-inserted for optimal performance
- Database is indexed for fast filtering
- UI updates are debounced to avoid excessive refreshes
- Old logs are automatically cleaned up

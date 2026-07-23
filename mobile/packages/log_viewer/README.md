# Log Viewer

A Flutter package that provides an in-app log viewer with advanced filtering capabilities for Ente apps.

## Features

- 📝 Real-time log capture and display
- 🔍 Advanced filtering by logger name, log level, and text search
- 🎨 Color-coded log levels for easy identification
- 📊 SQLite-based storage with automatic truncation
- 📤 Export filtered logs as text
- ⚡ Performance optimized with batch inserts and indexing
- 🏷️ Optional prefix support for multi-process logging

## Usage

### 1. Initialize in your app

```dart
import 'package:log_viewer/log_viewer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize log viewer (basic)
  await LogViewer.initialize();

  // Or with a prefix for multi-process apps
  await LogViewer.initialize(prefix: '[MAIN]');

  runApp(MyApp());
}
```

### 2. Open the log viewer

```dart
// As a navigation action
LogViewer.openViewer(context);

// Or embed as a widget
LogViewer.getViewerPage()
```

### 3. Automatic log capture

The log viewer automatically registers with `Logger.root.onRecord` to capture all logs from the logging package. No additional setup is required.

## Filtering Options

- **Logger Name**: Filter by specific loggers (e.g., "auth", "sync", "ui")
- **Log Level**: Filter by severity (SEVERE, WARNING, INFO, etc.)
- **Text Search**: Search within log messages and error descriptions
- **Time Range**: Filter logs by date/time range

## Database Management

- Logs are stored in a local SQLite database
- By default, automatic truncation keeps only the most recent 10000 entries
- Batch inserts for optimal performance

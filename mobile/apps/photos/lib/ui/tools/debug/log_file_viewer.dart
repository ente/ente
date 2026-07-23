import "dart:io";

import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/ui/common/loading_widget.dart";

class LogFileViewer extends StatefulWidget {
  final File file;
  const LogFileViewer(this.file, {super.key});

  @override
  State<LogFileViewer> createState() => _LogFileViewerState();
}

class _LogFileViewerState extends State<LogFileViewer> {
  static const _maxLinesToShow = 2000;

  late final Future<List<String>> _logsFuture;

  @override
  void initState() {
    super.initState();
    _logsFuture = _readLogs();
  }

  Future<List<String>> _readLogs() async {
    final logs = await widget.file.readAsLines();
    if (logs.length <= _maxLinesToShow) {
      return logs;
    }
    return logs.sublist(logs.length - _maxLinesToShow);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(AppLocalizations.of(context).todaysLogs),
      ),
      body: FutureBuilder<List<String>>(
        future: _logsFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          if (!snapshot.hasData) {
            return const EnteLoadingWidget();
          }
          final logs = snapshot.data!;
          return Scrollbar(
            interactive: true,
            thickness: 4,
            radius: const Radius.circular(2),
            child: ListView.builder(
              padding: const EdgeInsets.only(left: 12, top: 8, right: 12),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                return Text(
                  logs[index],
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                    height: 1.2,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

import 'dart:io';

import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/ui/common/loading_widget.dart';
import 'package:ente_auth/utils/platform_util.dart';
import 'package:flutter/material.dart';

class LogFileViewer extends StatefulWidget {
  final File file;
  const LogFileViewer(this.file, {super.key});

  @override
  State<LogFileViewer> createState() => _LogFileViewerState();
}

class _LogFileViewerState extends State<LogFileViewer> {
  String? _logs;
  @override
  void initState() {
    widget.file.readAsString().then((logs) {
      setState(() {
        _logs = logs;
      });
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(elevation: 0, title: Text(context.l10n.todaysLogs)),
      body: _getBody(),
    );
  }

  Widget _getBody() {
    if (_logs == null) {
      return const EnteLoadingWidget();
    }
    return Container(
      padding: const EdgeInsets.only(left: 12, top: 8, right: 12),
      child: SingleChildScrollView(
        child: SelectableRegion(
          focusNode: FocusNode(),
          selectionControls: PlatformUtil.selectionControls,
          child: Text(
            _logs!,
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

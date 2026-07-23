import 'dart:io';

import 'package:ente_ui/components/loading_widget.dart';
import 'package:flutter/cupertino.dart';
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
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text("Today's logs"),
      ),
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
          selectionControls: Platform.isAndroid
              ? materialTextSelectionControls
              : Platform.isIOS
              ? cupertinoTextSelectionControls
              : desktopTextSelectionControls,
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

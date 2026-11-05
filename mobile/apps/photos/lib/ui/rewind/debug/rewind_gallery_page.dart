import "package:flutter/material.dart";
import "package:photos/ui/rewind/debug/sample_reports.dart";
import "package:photos/ui/rewind/shell/rewind_viewer.dart";
import "package:photos/ui/rewind/story/rewind_composer.dart";

class RewindGalleryPage extends StatelessWidget {
  const RewindGalleryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Ente Rewind gallery")),
      body: ListView(
        children: [
          for (final sample in rewindSampleReports.entries)
            ListTile(
              title: Text(sample.key),
              trailing: const Icon(Icons.chevron_right_outlined),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      RewindViewer(pages: composeRewind(sample.value)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

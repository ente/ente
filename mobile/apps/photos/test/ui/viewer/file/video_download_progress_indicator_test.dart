import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/viewer/file/video_download_progress_indicator.dart";

void main() {
  testWidgets("centers determinate video download progress", (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: VideoDownloadProgressIndicator(progress: 0.42)),
        ),
      ),
    );

    final ring = find.byType(CircularProgressIndicator);
    final percentage = find.text("42%");

    expect(tester.getSize(ring), const Size.square(32));
    expect(tester.getCenter(ring), tester.getCenter(percentage));
  });
}

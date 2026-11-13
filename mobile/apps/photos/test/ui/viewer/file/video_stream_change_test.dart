import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/models/preview/preview_item_status.dart";
import "package:photos/ui/viewer/file/video_stream_change.dart";

void main() {
  testWidgets("uses the existing stream switch copy in viewer chrome", (
    tester,
  ) async {
    const noop = _NoopCallback();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: StringsLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Column(
            children: [
              Text(
                VideoStreamChangeState(
                  isPreviewPlayer: true,
                  isCurrentlyProcessing: false,
                  processingStatus: null,
                  onStreamChange: noop.call,
                ).label(context),
              ),
              Text(
                VideoStreamChangeState(
                  isPreviewPlayer: false,
                  isCurrentlyProcessing: false,
                  processingStatus: null,
                  onStreamChange: noop.call,
                ).label(context),
              ),
              Text(
                VideoStreamChangeState(
                  isPreviewPlayer: false,
                  isCurrentlyProcessing: true,
                  processingStatus: PreviewItemStatus.inQueue,
                  onStreamChange: noop.call,
                ).label(context),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text("Play original"), findsOneWidget);
    expect(find.text("Play stream"), findsOneWidget);
    expect(find.text("Queued"), findsOneWidget);
  });

  test("a retiring player cannot clear a replacement player's action", () {
    final controller = VideoStreamChangeController();
    final firstOwner = Object();
    final replacementOwner = Object();
    void noop() {}
    final state = VideoStreamChangeState(
      isPreviewPlayer: true,
      isCurrentlyProcessing: false,
      processingStatus: null,
      onStreamChange: noop,
    );

    controller.update(firstOwner, state);
    controller.update(replacementOwner, state);
    controller.clear(firstOwner);

    expect(controller.value, same(state));
    controller.dispose();
  });
}

class _NoopCallback {
  const _NoopCallback();

  void call() {}
}

import 'dart:io';
import 'dart:ui';

import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photos/ente_theme_data.dart';
import 'package:photos/ui/tools/editor/video_editor/video_editor_controller.dart';
import 'package:photos/ui/tools/editor/video_editor/video_editor_widgets.dart';

void main() {
  testWidgets('system back restores state while Done keeps it', (tester) async {
    final controller = VideoEditorController.file(File('unused.mp4'));
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: darkThemeData,
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: StringsLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => _SubPage(controller)),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('change-crop')));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(controller.minCrop, Offset.zero);
    expect(controller.maxCrop, const Offset(1, 1));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('change-crop')));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(controller.minCrop, const Offset(0.1, 0.2));
    expect(controller.maxCrop, const Offset(0.8, 0.9));
  });
}

class _SubPage extends StatelessWidget {
  const _SubPage(this.controller);

  final VideoEditorController controller;

  @override
  Widget build(BuildContext context) {
    return VideoEditorSubPage(
      controller: controller,
      preview: const ColoredBox(color: Colors.black),
      actions: TextButton(
        key: const Key('change-crop'),
        onPressed: () => controller.updateCrop(
          const Offset(0.1, 0.2),
          const Offset(0.8, 0.9),
        ),
        child: const Text('Change crop'),
      ),
    );
  }
}

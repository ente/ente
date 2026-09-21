import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photos/ente_theme_data.dart';
import 'package:photos/ui/common/video_speed_options.dart';

void main() {
  testWidgets('selecting a speed updates the visible choice', (tester) async {
    double selectedSpeed = 1.0;

    await tester.pumpWidget(
      MaterialApp(
        theme: darkThemeData,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => VideoSpeedOptions(
              currentSpeed: selectedSpeed,
              onSpeedSelected: (speed) {
                setState(() => selectedSpeed = speed);
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('1x'), findsOneWidget);
    await tester.tap(find.text('0.5x'));
    await tester.pump();
    expect(selectedSpeed, 0.5);
    expect(
      tester
          .widget<VideoSpeedOptions>(find.byType(VideoSpeedOptions))
          .currentSpeed,
      0.5,
    );
  });

  testWidgets('speed chips can be activated through semantics', (tester) async {
    double selectedSpeed = 1.0;

    await tester.pumpWidget(
      MaterialApp(
        theme: darkThemeData,
        home: Scaffold(
          body: VideoSpeedOptions(
            currentSpeed: selectedSpeed,
            onSpeedSelected: (speed) => selectedSpeed = speed,
          ),
        ),
      ),
    );

    final chip = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '0.5x',
      ),
    );
    expect(chip.properties.button, isTrue);
    expect(chip.properties.onTap, isNotNull);
    chip.properties.onTap!();
    expect(selectedSpeed, 0.5);
  });
}

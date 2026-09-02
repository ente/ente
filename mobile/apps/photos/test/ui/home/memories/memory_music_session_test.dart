import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/home/memories/memory_music_session.dart";

void main() {
  testWidgets("updates mute state before the controller is ready", (
    tester,
  ) async {
    var isMuted = true;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return MemoryMusicScope(
              controller: null,
              isMuted: isMuted,
              toggleMuted: () async {
                setState(() => isMuted = !isMuted);
              },
              child: const _MuteButton(),
            );
          },
        ),
      ),
    );

    expect(find.text("muted"), findsOneWidget);

    await tester.tap(find.byType(TextButton));
    await tester.pump();

    expect(find.text("unmuted"), findsOneWidget);
  });
}

class _MuteButton extends StatelessWidget {
  const _MuteButton();

  @override
  Widget build(BuildContext context) {
    final memoryMusic = MemoryMusicScope.maybeOf(context)!;
    return TextButton(
      onPressed: memoryMusic.toggleMuted,
      child: Text(memoryMusic.isMuted ? "muted" : "unmuted"),
    );
  }
}

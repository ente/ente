import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/home/memories/memory_music_session.dart";

void main() {
  testWidgets("keeps music and video mute states independent", (tester) async {
    var isMusicMuted = true;
    var isVideoMuted = false;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return MemoryAudioScope(
              controller: null,
              isMusicMuted: isMusicMuted,
              isVideoMuted: isVideoMuted,
              toggleMusicMuted: () async {
                setState(() => isMusicMuted = !isMusicMuted);
              },
              toggleVideoMuted: () async {
                setState(() => isVideoMuted = !isVideoMuted);
              },
              child: const _MuteButtons(),
            );
          },
        ),
      ),
    );

    expect(find.text("music muted"), findsOneWidget);
    expect(find.text("video unmuted"), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey("music-mute")));
    await tester.pump();

    expect(find.text("music unmuted"), findsOneWidget);
    expect(find.text("video unmuted"), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey("video-mute")));
    await tester.pump();

    expect(find.text("music unmuted"), findsOneWidget);
    expect(find.text("video muted"), findsOneWidget);
  });
}

class _MuteButtons extends StatelessWidget {
  const _MuteButtons();

  @override
  Widget build(BuildContext context) {
    final memoryAudio = MemoryAudioScope.maybeOf(context)!;
    return Column(
      children: [
        TextButton(
          key: const ValueKey("music-mute"),
          onPressed: memoryAudio.toggleMusicMuted,
          child: Text(
            memoryAudio.isMusicMuted ? "music muted" : "music unmuted",
          ),
        ),
        TextButton(
          key: const ValueKey("video-mute"),
          onPressed: memoryAudio.toggleVideoMuted,
          child: Text(
            memoryAudio.isVideoMuted ? "video muted" : "video unmuted",
          ),
        ),
      ],
    );
  }
}

import "package:flutter_test/flutter_test.dart";
import "package:photos/settings/local_settings.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    "existing memories audio preference remains the music preference",
    () async {
      SharedPreferences.setMockInitialValues({"memories.audio_muted": true});
      final settings = LocalSettings(await SharedPreferences.getInstance());

      expect(settings.isMemoriesMusicMuted(), isTrue);
      expect(settings.isMemoriesVideoMuted(), isFalse);
    },
  );

  test(
    "memories video mute is independent from music and file videos",
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = LocalSettings(await SharedPreferences.getInstance());

      await settings.setMemoriesMusicMuted(true);
      expect(settings.isMemoriesMusicMuted(), isTrue);
      expect(settings.isMemoriesVideoMuted(), isFalse);
      expect(settings.isMuted(), isFalse);

      await settings.setMemoriesVideoMuted(true);
      expect(settings.isMemoriesMusicMuted(), isTrue);
      expect(settings.isMemoriesVideoMuted(), isTrue);
      expect(settings.isMuted(), isFalse);

      await settings.setIsMuted(true);
      await settings.setMemoriesVideoMuted(false);
      expect(settings.isMemoriesMusicMuted(), isTrue);
      expect(settings.isMemoriesVideoMuted(), isFalse);
      expect(settings.isMuted(), isTrue);
    },
  );
}

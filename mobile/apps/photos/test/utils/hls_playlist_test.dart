import 'package:flutter_test/flutter_test.dart';
import 'package:photos/utils/hls_playlist.dart';

const playlist = '''#EXTM3U
#EXT-X-MEDIA-SEQUENCE:42
#EXT-X-VERSION:7
#EXT-X-TARGETDURATION:8
#EXT-X-KEY:METHOD=AES-128,URI="data:text/plain;base64,XjvG7qeRrsOpPUbJPh2Ikg==",IV=0x00000000000000000000000000000000
#EXTINF:8.333333,
#EXT-X-BYTERANGE:3046928@0
video.ts
#EXTINF:2.200000,
#EXT-X-BYTERANGE:834736
video.ts
#EXT-X-ENDLIST
''';

void main() {
  group('reconstructHlsPlaylist', () {
    test('reconstructs an allowed single-file playlist', () {
      const segmentUrl = 'https://museum.example/video?token=secret';

      expect(
        reconstructHlsPlaylist(playlist, segmentUrl),
        playlist.replaceAll('video.ts', segmentUrl),
      );
    });

    test('replaces every untrusted URI line', () {
      const segmentUrl = 'https://museum.example/video';
      final input = playlist.replaceFirst('video.ts', 'https://attacker');

      expect(
        reconstructHlsPlaylist(input, segmentUrl),
        playlist.replaceAll('video.ts', segmentUrl),
      );
    });

    final invalidPlaylists = {
      'remote key': playlist.replaceFirst(
        'data:text/plain;base64,XjvG7qeRrsOpPUbJPh2Ikg==',
        'https://attacker/key',
      ),
      'map': playlist.replaceFirst(
        '#EXTINF:8.333333,',
        '#EXT-X-MAP:URI="https://attacker/map"\n#EXTINF:8.333333,',
      ),
    };

    for (final entry in invalidPlaylists.entries) {
      test('rejects a playlist with an unexpected ${entry.key}', () {
        expect(
          () => reconstructHlsPlaylist(entry.value, 'https://museum/video'),
          throwsFormatException,
        );
      });
    }
  });
}

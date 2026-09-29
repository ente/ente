import "dart:convert";

const maxHlsMetadataBytes = 8 * 1024 * 1024;
const maxHlsPlaylistBytes = 32 * 1024 * 1024;

final _allowedTag = RegExp(
  r'^#(?:EXTM3U|EXT-X-(?:VERSION:\d+|TARGETDURATION:\d+|MEDIA-SEQUENCE:\d+|KEY:METHOD=AES-128,URI="data:text/plain;base64,[A-Za-z0-9+/]{22}==",IV=0x[0-9a-fA-F]{32}|BYTERANGE:\d+(?:@\d+)?|ENDLIST)|EXTINF:\d+(?:\.\d+)?,$)$',
);

String reconstructHlsPlaylist(String template, String segmentUrl) {
  if (RegExp(r'\r(?!\n)').hasMatch(template)) {
    throw const FormatException('Invalid HLS playlist');
  }
  final result = <String>[];
  final segmentUrlBytes = utf8.encode(segmentUrl).length;
  var outputBytes = 0;
  var hasKey = false;
  var hasSegment = false;
  for (var line in LineSplitter.split(template)) {
    if (line.isEmpty || (line.startsWith('#') && !line.startsWith('#EXT'))) {
      continue;
    }
    if (!line.startsWith('#')) {
      line = segmentUrl;
      outputBytes += segmentUrlBytes;
      hasSegment = true;
    } else if (_allowedTag.hasMatch(line)) {
      outputBytes += line.length;
      hasKey |= line.startsWith('#EXT-X-KEY:');
    } else {
      throw const FormatException('Invalid HLS playlist');
    }
    outputBytes += 1;
    if (outputBytes > maxHlsPlaylistBytes) {
      throw const FormatException("HLS playlist exceeds the allowed size");
    }
    result.add(line);
  }

  if (!hasKey ||
      !hasSegment ||
      result.first != '#EXTM3U' ||
      result.last != '#EXT-X-ENDLIST') {
    throw const FormatException('Invalid HLS playlist');
  }
  return (result..add('')).join('\n');
}

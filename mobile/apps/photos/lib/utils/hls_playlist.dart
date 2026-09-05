final _allowedTag = RegExp(
  r'^#(?:EXTM3U|EXT-X-(?:VERSION:\d+|TARGETDURATION:\d+|MEDIA-SEQUENCE:\d+|KEY:METHOD=AES-128,URI="data:text/plain;base64,[A-Za-z0-9+/]{22}==",IV=0x[0-9a-fA-F]{32}|BYTERANGE:\d+(?:@\d+)?|ENDLIST)|EXTINF:\d+(?:\.\d+)?,$)$',
);

String reconstructHlsPlaylist(String template, String segmentUrl) {
  final result = <String>[];
  var hasKey = false;
  var hasSegment = false;
  for (final line in template.split(RegExp(r'\r?\n'))) {
    if (line.isEmpty || (line.startsWith('#') && !line.startsWith('#EXT'))) {
      continue;
    }
    if (!line.startsWith('#')) {
      result.add(segmentUrl);
      hasSegment = true;
    } else if (_allowedTag.hasMatch(line)) {
      result.add(line);
      hasKey |= line.startsWith('#EXT-X-KEY:');
    } else {
      throw const FormatException('Invalid HLS playlist');
    }
  }

  if (!hasKey ||
      !hasSegment ||
      result.first != '#EXTM3U' ||
      result.last != '#EXT-X-ENDLIST') {
    throw const FormatException('Invalid HLS playlist');
  }
  return '${result.join('\n')}\n';
}

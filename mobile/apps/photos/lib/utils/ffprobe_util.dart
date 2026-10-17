// Adapted from: https://github.com/deckerst/aves

import "package:photos/models/ffmpeg/ffprobe_keys.dart";

class FFProbeUtil {
  static const chaptersKey = 'chapters';
  static const formatKey = 'format';
  static const streamsKey = 'streams';

  static Map getMetadata(Map props) {
    final chapters = props[chaptersKey];
    if (chapters is List) {
      if (chapters.isEmpty) {
        props.remove(chaptersKey);
      }
    }

    final format = props.remove(formatKey);
    if (format is Map) {
      format.remove(FFProbeKeys.filename);
      format.remove('size');
      _normalizeGroup(format);
      props.addAll(format);
    }

    final streams = props[streamsKey];
    if (streams is List) {
      for (var stream in streams) {
        if (stream is Map) {
          _normalizeGroup(stream);

          final fps = stream[FFProbeKeys.avgFrameRate];
          if (fps is String) {
            final parts = fps.split('/');
            if (parts.length == 2) {
              final num = int.tryParse(parts[0]);
              final den = int.tryParse(parts[1]);
              if (num != null && den != null) {
                if (den > 0) {
                  stream[FFProbeKeys.fpsNum] = num;
                  stream[FFProbeKeys.fpsDen] = den;
                }
                stream.remove(FFProbeKeys.avgFrameRate);
              }
            }
          }

          final disposition = stream[FFProbeKeys.disposition];
          if (disposition is Map) {
            disposition.removeWhere((key, value) => value == 0);
            stream[FFProbeKeys.disposition] = disposition.keys.join(', ');
          }

          final idValue = stream['id'];
          if (idValue is String) {
            final id = int.tryParse(idValue);
            if (id != null) {
              stream[FFProbeKeys.index] = id - 1;
              stream.remove('id');
            }
          }

          if (stream[FFProbeKeys.streamType] == 'data') {
            stream[FFProbeKeys.streamType] = MediaStreamTypes.metadata;
          }
        }
      }
    }
    return props;
  }

  static void _normalizeGroup(Map<dynamic, dynamic> stream) {
    void replaceKey(k1, k2) {
      final v = stream.remove(k1);
      if (v != null) {
        stream[k2] = v;
      }
    }

    replaceKey('bit_rate', FFProbeKeys.bitrate);
    replaceKey('codec_type', FFProbeKeys.streamType);
    replaceKey('format_name', FFProbeKeys.mediaFormat);
    replaceKey('level', FFProbeKeys.codecLevel);
    replaceKey('nb_frames', FFProbeKeys.frameCount);
    replaceKey('pix_fmt', FFProbeKeys.codecPixelFormat);
    replaceKey('profile', FFProbeKeys.codecProfileId);

    final tags = stream.remove('tags');
    if (tags is Map) {
      stream.addAll(tags);
    }

    for (var key in <String>{
      FFProbeKeys.bitrate,
      FFProbeKeys.codecProfileId,
      FFProbeKeys.colorPrimaries,
      FFProbeKeys.colorRange,
      FFProbeKeys.colorSpace,
      FFProbeKeys.colorTransfer,
      FFProbeKeys.frameCount,
      FFProbeKeys.rFrameRate,
      'bits_per_sample',
      'closed_captions',
      'codec_long_name',
      'film_grain',
      'has_b_frames',
      'start_pts',
      'start_time',
      'vendor_id',
    }) {
      final value = stream[key];
      switch (value) {
        case final num v:
          if (v == 0) {
            stream.remove(key);
          }
        case final String v:
          if (double.tryParse(v) == 0 ||
              v == '0/0' ||
              v == 'unknown' ||
              v == '[0][0][0][0]') {
            stream.remove(key);
          }
      }
    }
  }
}

// Adapted from: https://github.com/deckerst/aves

import "dart:developer";

import "package:intl/intl.dart";
import "package:photos/models/ffmpeg/channel_layouts.dart";
import "package:photos/models/ffmpeg/codecs.dart";
import "package:photos/models/ffmpeg/ffprobe_keys.dart";
import "package:photos/models/ffmpeg/mp4.dart";
import "package:photos/models/location/location.dart";

class FFProbeProps {
  Map<String, dynamic>? propData;
  Location? location;
  DateTime? creationTimeUTC;
  String? bitrate;
  String? majorBrand;
  String? fps;
  String? _width;
  String? _height;
  int? _rotation;
  Duration? duration;

  // dot separated bitrate, fps, codecWidth, codecHeight. Ignore null value
  String get videoInfo {
    final List<String> info = [];
    if (bitrate != null) info.add('$bitrate');
    if (fps != null) info.add('ƒ/$fps');
    if (_width != null && _height != null) {
      info.add('$_width x $_height');
    }
    return info.join(' * ');
  }

  int? get width {
    if (_width == null || _height == null) return null;
    int? finalWidth = int.tryParse(_width!);
    if (propData?[FFProbeKeys.sampleAspectRatio] != null &&
        finalWidth != null) {
      finalWidth = _calculateWidthConsideringSAR(finalWidth);
    }
    if (_rotation != null) {
      if ((_rotation! ~/ 90).isOdd) {
        finalWidth = int.tryParse(_height!);
      }
    }
    return finalWidth;
  }

  /// To know more, read about Sample Aspect Ratio (SAR), Display Aspect Ratio (DAR)
  /// and Pixel Aspect Ratio (PAR)
  int _calculateWidthConsideringSAR(int width) {
    final List<String> sar = propData![FFProbeKeys.sampleAspectRatio]
        .toString()
        .split(":");
    if (sar.length == 2) {
      final int sarWidth = int.tryParse(sar[0]) ?? 1;
      final int sarHeight = int.tryParse(sar[1]) ?? 1;
      return (width * (sarWidth / sarHeight)).toInt();
    } else {
      return width;
    }
  }

  int? get height {
    if (_width == null || _height == null) return null;
    final intHeight = int.tryParse(_height!);
    if (_rotation == null) {
      return intHeight;
    } else {
      if ((_rotation! ~/ 90).isEven) {
        return intHeight;
      } else {
        return int.tryParse(_width!);
      }
    }
  }

  double? get aspectRatio {
    if (width == null || height == null || height == 0 || width == 0) {
      return null;
    }
    return width! / height!;
  }

  int? get rotation => _rotation;

  // toString() method
  @override
  String toString() {
    final buffer = StringBuffer();
    for (final key in propData!.keys) {
      final value = propData![key];
      if (value != null) {
        buffer.writeln('$key: $value');
      }
    }
    return buffer.toString();
  }

  static FFProbeProps parseData(Map<dynamic, dynamic>? json) {
    final Map<String, dynamic> parsedData = {};
    final FFProbeProps result = FFProbeProps();

    for (final key in json!.keys) {
      final stringKey = key.toString();

      switch (stringKey) {
        case FFProbeKeys.bitrate:
        case FFProbeKeys.bps:
          result.bitrate = formatBitrate(json[key], 'b/s');
          parsedData[stringKey] = result.bitrate;
          break;
        case FFProbeKeys.byteCount:
          parsedData[stringKey] = _formatFilesize(json[key]);
          break;
        case FFProbeKeys.channelLayout:
          parsedData[stringKey] = _formatChannelLayout(json[key]);
          break;
        case FFProbeKeys.codecName:
          parsedData[stringKey] = _formatCodecName(json[key]);
          break;
        case FFProbeKeys.codecPixelFormat:
        case FFProbeKeys.colorPrimaries:
        case FFProbeKeys.colorRange:
        case FFProbeKeys.colorSpace:
        case FFProbeKeys.colorTransfer:
          parsedData[stringKey] = (json[key] as String?)?.toUpperCase();
          break;
        case FFProbeKeys.creationTime:
          parsedData[stringKey] = _formatDate(json[key] ?? "");
          result.creationTimeUTC = _getUTCDateTime(json[key] ?? "");
          break;
        case FFProbeKeys.durationMicros:
          parsedData[stringKey] = formatPreciseDuration(
            Duration(microseconds: int.tryParse(json[key] ?? "") ?? 0),
          );
          break;
        case FFProbeKeys.duration:
          parsedData[stringKey] = _formatDuration(json[key]);
          result.duration = _parseDuration(json[key]);
        case FFProbeKeys.location:
          result.location = _formatLocation(json[key]);
          if (result.location != null) {
            parsedData[stringKey] =
                '${result.location!.latitude}, ${result.location!.longitude}';
          }
          break;
        case FFProbeKeys.quickTimeLocation:
          result.location = _formatLocation(
            json[FFProbeKeys.quickTimeLocation],
          );
          if (result.location != null) {
            parsedData[FFProbeKeys.location] =
                '${result.location!.latitude}, ${result.location!.longitude}';
          }
          break;
        case FFProbeKeys.majorBrand:
          result.majorBrand = _formatBrand(json[key]);
          parsedData[stringKey] = result.majorBrand;
          break;
        case FFProbeKeys.startTime:
          parsedData[stringKey] = _formatDuration(json[key]);
          break;
        default:
          parsedData[stringKey] = json[key];
      }
    }
    // iterate through the streams
    final List<dynamic> streams = json["streams"];
    final List<dynamic> newStreams = [];
    final Map<String, dynamic> metadata = {};
    for (final stream in streams) {
      if (stream['type'] == 'metadata') {
        for (final key in stream.keys) {
          if (key == FFProbeKeys.frameCount && stream[key]?.toString() == "1") {
            continue;
          }
          metadata[key] = stream[key];
        }
        metadata.remove(FFProbeKeys.index);
      } else {
        newStreams.add(stream);
      }
      for (final key in stream.keys) {
        if (key == FFProbeKeys.rFrameRate) {
          result.fps = _formatFPS(stream[key]);
          parsedData[key] = result.fps;
        }
        //TODO: Use `height` and `width` instead of `codedHeight` and `codedWidth`
        //for better accuracy. `height' and `width` will give the video's "visual"
        //height and width.
        else if (key == FFProbeKeys.codedWidth) {
          final width = stream[key];
          if (width != null && width != 0) {
            result._width = width.toString();
            parsedData[key] = result._width;
          }
        } else if (key == FFProbeKeys.codedHeight) {
          final height = stream[key];
          if (height != null && height != 0) {
            result._height = height.toString();
            parsedData[key] = result._height;
          }
        } else if (key == FFProbeKeys.width) {
          final width = stream[key];
          if (width != null && width != 0) {
            result._width = width.toString();
            parsedData[key] = result._width;
          }
        } else if (key == FFProbeKeys.height) {
          final height = stream[key];
          if (height != null && height != 0) {
            result._height = height.toString();
            parsedData[key] = result._height;
          }
        } else if (key == FFProbeKeys.sideDataList) {
          for (Map sideData in stream[key]) {
            if (sideData["side_data_type"] == "Display Matrix") {
              result._rotation = sideData[FFProbeKeys.rotation];
              parsedData[FFProbeKeys.rotation] = result._rotation;
            }
          }
        } else if (key == FFProbeKeys.sampleAspectRatio) {
          parsedData[key] = stream[key];
        }
      }
    }
    if (metadata.isNotEmpty) {
      newStreams.add(metadata);
    }
    parsedData["streams"] = newStreams;
    result.propData = parsedData;
    return result;
  }

  static String _formatBrand(String value) => Mp4.brands[value] ?? value;

  static String _formatChannelLayout(dynamic value) {
    if (value is int) {
      return ChannelLayouts.names[value] ?? 'unknown ($value)';
    }
    return '$value';
  }

  static final Map<String, String> _codecNames = {
    Codecs.ac3: 'AC-3',
    Codecs.eac3: 'E-AC-3',
    Codecs.h264: 'AVC (H.264)',
    Codecs.hevc: 'HEVC (H.265)',
    Codecs.matroska: 'Matroska',
    Codecs.mpeg4: 'MPEG-4 Visual',
    Codecs.mpts: 'MPEG-TS',
    Codecs.opus: 'Opus',
    Codecs.pgs: 'PGS',
    Codecs.subrip: 'SubRip',
    Codecs.theora: 'Theora',
    Codecs.vorbis: 'Vorbis',
    Codecs.webm: 'WebM',
  };

  static String? _formatCodecName(String? value) =>
      value == null || value == "none"
      ? null
      : _codecNames[value] ?? value.toUpperCase().replaceAll('_', ' ');

  // input example: '2021-04-12T09:14:37.000000Z'
  static String? _formatDate(String value) {
    final dateInUtc = DateTime.tryParse(value);
    if (dateInUtc == null) return value;
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    if (dateInUtc == epoch) return null;
    final newDate = DateTime.fromMicrosecondsSinceEpoch(
      dateInUtc.microsecondsSinceEpoch,
    );
    return formatDateTime(newDate, 'en_US', false);
  }

  static DateTime? _getUTCDateTime(String value) {
    final dateInUtc = DateTime.tryParse(value);
    if (dateInUtc == null) return null;
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    if (dateInUtc == epoch) return null;
    return DateTime.fromMicrosecondsSinceEpoch(
      dateInUtc.microsecondsSinceEpoch,
    );
  }

  // input example: '00:00:05.408000000' or '5.408000'
  static Duration? _parseDuration(String? value) {
    if (value == null) return null;

    var match = _durationHmsmPattern.firstMatch(value);
    if (match != null) {
      final h = int.tryParse(match.group(1)!);
      final m = int.tryParse(match.group(2)!);
      final s = int.tryParse(match.group(3)!);
      final millis = double.tryParse(match.group(4)!);
      if (h != null && m != null && s != null && millis != null) {
        return Duration(
          hours: h,
          minutes: m,
          seconds: s,
          milliseconds: (millis * 1000).toInt(),
        );
      }
    }

    match = _durationSmPattern.firstMatch(value);
    if (match != null) {
      final s = int.tryParse(match.group(1)!);
      final millis = double.tryParse(match.group(2)!);
      if (s != null && millis != null) {
        return Duration(seconds: s, milliseconds: (millis * 1000).toInt());
      }
    }

    return null;
  }

  // input example: '00:00:05.408000000' or '5.408000'
  static String? _formatDuration(String? value) {
    if (value == null) return null;
    final duration = _parseDuration(value);
    return duration != null ? formatFriendlyDuration(duration) : value;
  }

  static String? _formatFilesize(dynamic value) {
    if (value == null) return null;
    final size = value is int ? value : int.tryParse(value);
    const String asciiLocale = 'en_US';
    return size != null ? formatFileSize(asciiLocale, size) : value;
  }

  static String? _formatFPS(dynamic value) {
    if (value == null) return null;
    final int? t = int.tryParse(value.split('/')[0]);
    final int? b = int.tryParse(value.split('/')[1]);
    if (t != null && b != null) {
      // return the value upto 2 decimal places. ignore even two decimal places
      // if t is perfectly divisible by b
      return (t % b == 0)
          ? (t / b).toStringAsFixed(0)
          : (t / b).toStringAsFixed(2);
    }
    return value;
  }

  static final _durationHmsmPattern = RegExp(r'(\d+):(\d+):(\d+)(.\d+)');
  static final _durationSmPattern = RegExp(r'(\d+)(.\d+)');
  static final _locationPattern = RegExp(r'([+-][.0-9]+)');

  // format ISO 6709 input, e.g. '+37.5090+127.0243/' (Samsung), '+51.3328-000.7053+113.474/' (Apple)
  static Location? _formatLocation(String? value) {
    if (value == null) return null;
    final matches = _locationPattern.allMatches(value);
    if (matches.isNotEmpty) {
      final coordinates = matches
          .map((m) => double.tryParse(m.group(0)!))
          .toList();
      if (coordinates.every((c) => c == 0)) return null;
      try {
        return Location(latitude: coordinates[0], longitude: coordinates[1]);
      } catch (e) {
        log('failed to parse location: $value', error: e);
        return null;
      }
    }
    return null;
  }

  static String? formatBitrate(dynamic size, String unit, {int round = 2}) {
    if (size == null) return null;
    if (size is String) {
      final parsed = int.tryParse(size);
      if (parsed == null) return size;
      size = parsed;
    }

    const divider = 1000;
    if (size < divider) return '$size $unit';
    if (size < divider * divider) {
      return '${(size / divider).toStringAsFixed(round)} K$unit';
    }
    return '${(size / divider / divider).toStringAsFixed(round)} M$unit';
  }
}

String formatDay(DateTime date, String locale) =>
    DateFormat.yMMMd(locale).format(date);

String formatTime(DateTime date, String locale, bool use24hour) =>
    (use24hour ? DateFormat.Hm(locale) : DateFormat.jm(locale)).format(date);

String formatDateTime(DateTime date, String locale, bool use24hour) =>
    [formatDay(date, locale), formatTime(date, locale, use24hour)].join(" ");

String formatFriendlyDuration(Duration d) {
  final seconds = (d.inSeconds.remainder(
    Duration.secondsPerMinute,
  )).toString().padLeft(2, '0');
  if (d.inHours == 0) return '${d.inMinutes}:$seconds';

  final minutes = (d.inMinutes.remainder(
    Duration.minutesPerHour,
  )).toString().padLeft(2, '0');
  return '${d.inHours}:$minutes:$seconds';
}

String? formatPreciseDuration(Duration d) {
  if (d.inSeconds == 0) return null;
  final millis = ((d.inMicroseconds / 1000.0).round() % 1000)
      .toString()
      .padLeft(3, '0');
  final seconds = (d.inSeconds.remainder(
    Duration.secondsPerMinute,
  )).toString().padLeft(2, '0');
  final minutes = (d.inMinutes.remainder(
    Duration.minutesPerHour,
  )).toString().padLeft(2, '0');
  final hours = (d.inHours).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds.$millis';
}

const kilo = 1024;
const mega = kilo * kilo;
const giga = mega * kilo;
const tera = giga * kilo;

String formatFileSize(String locale, int size, {int round = 2}) {
  if (size < kilo) return '$size B';

  final compactFormatter = NumberFormat(
    '0${round > 0 ? '.${'0' * round}' : ''}',
    locale,
  );
  if (size < mega) return '${compactFormatter.format(size / kilo)} KB';
  if (size < giga) return '${compactFormatter.format(size / mega)} MB';
  if (size < tera) return '${compactFormatter.format(size / giga)} GB';
  return '${compactFormatter.format(size / tera)} TB';
}

// Adapted from: https://github.com/deckerst/aves/blob/4a0009f4f0b63f2c4478e2531be8046c3b2e3320/plugins/aves_model/lib/src/video/keys.dart

class FFProbeKeys {
  static const androidCaptureFramerate = 'com.android.capture.fps';
  static const androidManufacturer = 'com.android.manufacturer';
  static const androidModel = 'com.android.model';
  static const androidVersion = 'com.android.version';
  static const avgFrameRate = 'avg_frame_rate';
  static const bps = 'bps';
  static const bitrate = 'bitrate';
  static const bitsPerRawSample = 'bits_per_raw_sample';
  static const byteCount = 'number_of_bytes';
  static const channelLayout = 'channel_layout';
  static const chromaLocation = 'chroma_location';
  static const codecName = 'codec_name';
  static const codecPixelFormat = 'codec_pixel_format';
  static const codecProfileId = 'codec_profile_id';
  static const codedHeight = 'coded_height';
  static const codecLevel = 'codec_level';
  static const codedWidth = 'coded_width';
  static const colorPrimaries = 'color_primaries';
  static const colorRange = 'color_range';
  static const colorSpace = 'color_space';
  static const colorTransfer = 'color_transfer';
  static const compatibleBrands = 'compatible_brands';
  static const creationTime = 'creation_time';
  static const dar = 'display_aspect_ratio';
  static const date = 'date';
  static const disposition = 'disposition';
  static const duration = 'duration';
  static const quickTimeLocation = "com.apple.quicktime.location.ISO6709";
  static const durationMicros = 'duration_us';
  static const encoder = 'encoder';
  static const extraDataSize = 'extradata_size';
  static const fieldOrder = 'field_order';
  static const filename = 'filename';
  static const fpsDen = 'fps_den';
  static const fpsNum = 'fps_num';
  static const frameCount = 'number_of_frames';
  static const handlerName = 'handler_name';
  static const hasBFrames = 'has_b_frames';
  static const height = 'height';
  static const index = 'index';
  static const language = 'language';
  static const location = 'location';
  static const majorBrand = 'major_brand';
  static const mediaFormat = 'format';
  static const mediaType = 'media_type';
  static const minorVersion = 'minor_version';
  static const nalLengthSize = 'nal_length_size';
  static const quicktimeLocationAccuracyHorizontal =
      'com.apple.quicktime.location.accuracy.horizontal';
  static const rFrameRate = 'r_frame_rate';
  static const rotate = 'rotate';
  static const sampleFormat = 'sample_fmt';
  static const sampleRate = 'sample_rate';
  static const sar = 'sample_aspect_ratio';
  static const sarDen = 'sar_den';
  static const sourceOshash = 'source_oshash';
  static const startMicros = 'start_us';
  static const startPts = 'start_pts';
  static const startTime = 'start_time';
  static const statisticsWritingApp = '_statistics_writing_app';
  static const statisticsWritingDateUtc = '_statistics_writing_date_utc';
  static const segmentCount = 'segment_count';
  static const streamType = 'type';
  static const title = 'title';
  static const timeBase = 'time_base';
  static const track = 'track';
  static const vendorId = 'vendor_id';
  static const width = 'width';
  static const xiaomiSlowMoment = 'com.xiaomi.slow_moment';
  static const sideDataList = 'side_data_list';
  static const rotation = 'rotation';
  static const sideDataType = 'side_data_type';
  static const sampleAspectRatio = 'sample_aspect_ratio';
}

class MediaStreamTypes {
  static const attachment = 'attachment';
  static const audio = 'audio';
  static const metadata = 'metadata';
  static const subtitle = 'subtitle';
  static const timedText = 'timedtext';
  static const unknown = 'unknown';
  static const video = 'video';
}

enum SideDataType {
  displayMatrix;

  String getString() {
    switch (this) {
      case SideDataType.displayMatrix:
        return 'Display Matrix';
    }
  }
}

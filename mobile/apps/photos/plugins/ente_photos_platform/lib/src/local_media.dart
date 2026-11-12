import 'package:flutter/services.dart';

class LocalMediaClient {
  static final instance = LocalMediaClient();
  static const _methodChannel = MethodChannel(
    'io.ente.photos.platform/local_media',
  );

  Future<bool?> assetExists(String localID) {
    return _methodChannel.invokeMethod<bool>('localMedia.assetExists', {
      'localID': localID,
    });
  }
}

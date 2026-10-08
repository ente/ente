import 'package:flutter/services.dart';

class MediaStoreClient {
  MediaStoreClient({MethodChannel? methodChannel})
    : _methodChannel = methodChannel ?? const MethodChannel(_methodChannelName);

  static final instance = MediaStoreClient();
  static const _methodChannelName = 'io.ente.photos.platform/media_store';

  final MethodChannel _methodChannel;

  Future<bool?> assetExists(String id) {
    return _methodChannel.invokeMethod<bool>('mediaStore.assetExists', {
      'id': id,
    });
  }
}

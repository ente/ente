import 'dart:typed_data';

import 'package:media_extension/media_extension_action_types.dart';
import 'package:media_extension/media_extension_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

abstract class MediaExtensionPlatform extends PlatformInterface {
  MediaExtensionPlatform() : super(token: _token);

  static final Object _token = Object();

  static MediaExtensionPlatform _instance = MethodChannelMediaExtension();

  static MediaExtensionPlatform get instance => _instance;

  static set instance(MediaExtensionPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<bool> setAs(
    String uri,
    String mimeType, {
    String title = 'Set as',
  }) async {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<bool> edit(
    String uri,
    String mimeType, {
    String title = 'Edit',
  }) async {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<bool> openWith(
    String uri,
    String mimeType, {
    String title = 'Open with',
  }) async {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<MediaExtentionAction> getIntentAction() async {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<Uint8List?> readUriBytes(String uri) async {
    throw UnimplementedError('readUriBytes() has not been implemented.');
  }

  Stream<MediaExtentionAction> get intentActionStream {
    throw UnimplementedError('intentActionStream has not been implemented.');
  }

  Future<void> setResult(String uri) async {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<void> setResults(List<String> uris) async {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<void> cancelResult() async {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}

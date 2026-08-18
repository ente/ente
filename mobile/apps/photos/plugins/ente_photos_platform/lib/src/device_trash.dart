import 'dart:io';

import 'package:flutter/services.dart';

class DeviceTrashFile {
  const DeviceTrashFile({
    required this.localID,
    required this.deleteBy,
    required this.deviceFolder,
  });

  factory DeviceTrashFile.fromMap(Map<dynamic, dynamic> map) => DeviceTrashFile(
    localID: map['localID'],
    deleteBy: map['deleteBy'],
    deviceFolder: map['deviceFolder'],
  );

  final int localID;

  /// The absolute deletion deadline in microseconds since the Unix epoch.
  final int deleteBy;

  final String deviceFolder;
}

class DeviceTrashClient {
  static final instance = DeviceTrashClient();
  static const _methodChannel = MethodChannel('io.ente.photos.platform');

  Future<List<DeviceTrashFile>> getFiles() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Device trash is only supported on Android');
    }
    try {
      final result = await _methodChannel
          .invokeListMethod<Map<dynamic, dynamic>>('deviceTrash.getFiles');
      return List.unmodifiable(result!.map(DeviceTrashFile.fromMap));
    } on PlatformException catch (error) {
      if (error.code == 'device_trash_unsupported') {
        throw UnsupportedError('Device trash requires Android 11 or newer');
      }
      rethrow;
    }
  }
}

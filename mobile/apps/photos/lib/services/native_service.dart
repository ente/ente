import "dart:io";

import "package:flutter/services.dart";

class NativeTrashFile {
  final int localID;
  final int deleteBy;
  final String deviceFolder;

  const NativeTrashFile({
    required this.localID,
    required this.deleteBy,
    required this.deviceFolder,
  });
}

class NativeService {
  NativeService._();

  static const _channel = MethodChannel("ente.io/photos/native");

  static Future<List<NativeTrashFile>> getTrash() async {
    if (!Platform.isAndroid) return const [];

    final files = await _channel.invokeListMethod<Object?>("getTrash") ?? [];
    return files.map((file) {
      final map = file! as Map<Object?, Object?>;
      return NativeTrashFile(
        localID: map["localID"]! as int,
        deleteBy: map["deleteBy"]! as int,
        deviceFolder: map["deviceFolder"]! as String,
      );
    }).toList();
  }
}

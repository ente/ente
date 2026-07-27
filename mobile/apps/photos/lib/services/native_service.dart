import "package:flutter/services.dart";

class NativeTrashFile {
  final String localID;
  final int deleteBy;

  const NativeTrashFile({required this.localID, required this.deleteBy});

  factory NativeTrashFile.fromMap(Map<Object?, Object?> map) {
    return NativeTrashFile(
      localID: map["localID"]! as String,
      deleteBy: map["deleteBy"]! as int,
    );
  }
}

class NativeService {
  NativeService._();

  static const _channel = MethodChannel("ente.io/photos/native");

  static Future<List<NativeTrashFile>> getTrash() async {
    final files = await _channel.invokeListMethod<Object?>("getTrash") ?? [];
    return files
        .map((file) => NativeTrashFile.fromMap(file! as Map<Object?, Object?>))
        .toList();
  }
}

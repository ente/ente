import "package:flutter/foundation.dart";

class RewindFace {
  RewindFace({this.name, Uint8List? crop}) : _crop = ValueNotifier(crop);

  final String? name;
  final ValueNotifier<Uint8List?> _crop;

  Uint8List? get crop => _crop.value;

  ValueListenable<Uint8List?> get liveCrop => _crop;

  void sharpen(Uint8List crop) => _crop.value = crop;
}

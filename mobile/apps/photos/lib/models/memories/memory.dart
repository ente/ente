import 'package:photos/models/file/file.dart';

class Memory {
  final EnteFile file;
  int _seenTime;

  Memory(this.file, this._seenTime);

  bool isSeen() {
    return _seenTime != -1;
  }

  int seenTime() {
    return _seenTime;
  }

  void markSeen() {
    _seenTime = DateTime.now().microsecondsSinceEpoch;
  }

  Memory.fromFile(this.file, Map<int, int>? seenTimes, {int? seenTimeKey})
    : _seenTime = seenTimes?[seenTimeKey ?? file.generatedID] ?? -1;

  static List<Memory> fromFiles(
    List<EnteFile> files,
    Map<int, int>? seenTimes,
  ) {
    final memories = <Memory>[];
    for (final file in files) {
      memories.add(Memory.fromFile(file, seenTimes));
    }
    return memories;
  }

  static List<EnteFile> filesFromMemories(List<Memory> memories) {
    final List<EnteFile> files = [];
    for (final memory in memories) {
      files.add(memory.file);
    }
    return files;
  }
}

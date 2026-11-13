import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

final _logRecordHeader = RegExp(
  r'^[ \t]*(?:\[[^\]]+\][ \t]+)?\[([^\]]+)\][ \t]*\[[A-Z]+\][ \t]+\[([0-9]{4}-[^\]]+)\][ \t]*(.*)',
);

class LogFileEntry {
  LogFileEntry._(this.text) : _header = _logRecordHeader.firstMatch(text);

  final RegExpMatch? _header;
  final String text;

  String? get loggerName => _header?.group(1);
  DateTime? get timestamp => DateTime.tryParse(_header?.group(2) ?? '');
  String? get message => _header?.group(3);
}

class LogFileReader {
  LogFileReader(this._file);

  static const _pageLineCount = 2000;
  static const _readChunkSize = 64 * 1024;

  final File _file;
  String? _continuedEntry;
  int _position = 0;

  bool get hasMore => _position > 0;

  Future<void> reset() async {
    _position = await _file.length();
    _continuedEntry = null;
  }

  Future<List<LogFileEntry>> readPreviousPage() async {
    final result = <LogFileEntry>[];
    while (result.isEmpty && hasMore) {
      final page = await _readPage(_position);
      _position = page.start;
      final entries = page.entries;
      if (entries.isEmpty) continue;

      final continuedEntry = _continuedEntry;
      if (continuedEntry != null) {
        entries.last = '${entries.last}\n$continuedEntry';
        _continuedEntry = null;
      }
      if (hasMore && page.firstEntryContinuesPrevious) {
        _continuedEntry = entries.removeAt(0);
      }
      result.addAll(entries.reversed.map(LogFileEntry._));
    }
    return result;
  }

  Future<({int start, List<String> entries, bool firstEntryContinuesPrevious})>
  _readPage(int end) async {
    final handle = await _file.open();
    try {
      var position = end;
      var newlineCount = 0;
      final chunks = <Uint8List>[];

      while (position > 0 && newlineCount <= _pageLineCount) {
        final length = min(_readChunkSize, position);
        position -= length;
        await handle.setPosition(position);
        final chunk = await handle.read(length);
        chunks.add(chunk);
        for (final byte in chunk) {
          if (byte == 10) newlineCount++;
        }
      }

      final bytes = BytesBuilder(copy: false);
      for (final chunk in chunks.reversed) {
        bytes.add(chunk);
      }
      var pageBytes = bytes.takeBytes();
      if (position > 0) {
        final firstNewline = pageBytes.indexOf(10);
        position += firstNewline + 1;
        pageBytes = Uint8List.sublistView(pageBytes, firstNewline + 1);
      }

      final lines = const LineSplitter().convert(utf8.decode(pageBytes));
      final entries = <List<String>>[];
      for (final line in lines) {
        if (entries.isEmpty || _logRecordHeader.hasMatch(line)) {
          entries.add([line]);
        } else {
          entries.last.add(line);
        }
      }
      return (
        start: position,
        entries: [for (final entry in entries) entry.join('\n')],
        firstEntryContinuesPrevious:
            lines.isNotEmpty && !_logRecordHeader.hasMatch(lines.first),
      );
    } finally {
      await handle.close();
    }
  }
}

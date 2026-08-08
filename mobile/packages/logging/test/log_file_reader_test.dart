import 'dart:io';

import 'package:ente_logging/logging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads every multiline entry across backward pages', () async {
    final directory = await Directory.systemTemp.createTemp('log-reader-');
    addTearDown(() => directory.delete(recursive: true));

    const first =
        '[main][INFO] [2026-08-08 09:12:00.000000] Starting app in foreground';
    const latest =
        '[bg] [sync] [SEVERE] [2026-08-08 22:23:00.000000] Latest record';
    final padding = List.filled(40, 'x').join();
    final continuation = List.generate(5000, (index) => '#$index $padding');
    final firstEntry = [first, ...continuation].join('\n');
    final file = File('${directory.path}/today.txt');
    await file.writeAsString('$firstEntry\n$latest\n');

    final reader = LogFileReader(file);
    await reader.reset();
    final entries = <LogFileEntry>[];
    while (reader.hasMore) {
      entries.addAll(await reader.readPreviousPage());
    }

    expect(entries.map((entry) => entry.text), [latest, firstEntry]);
    expect(entries.first.loggerName, 'sync');
    expect(entries.last.loggerName, 'main');
    expect(entries.last.message, 'Starting app in foreground');
  });
}

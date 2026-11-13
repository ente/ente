import 'dart:io';

import 'package:ente_auth/core/errors.dart';
import 'package:ente_auth/ui/settings/data/import/import_file_cleanup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enforces an optional byte limit without truncating imports', () async {
    final directory = await Directory.systemTemp.createTemp('auth-import-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/backup');
    await file.writeAsBytes([1, 2, 3, 4]);

    expect(await readPickedImportFileAsBytes(file.path, maxBytes: 4), [
      1,
      2,
      3,
      4,
    ]);
    await file.writeAsBytes([5], mode: FileMode.append);
    await expectLater(
      readPickedImportFileAsBytes(file.path, maxBytes: 4),
      throwsA(isA<ImportFileTooLargeException>()),
    );
    expect(await readPickedImportFileAsBytes(file.path), [1, 2, 3, 4, 5]);
  });
}

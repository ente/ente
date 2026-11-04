import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/src/rust/api/import_api.dart' as rust;
import 'package:ente_auth/ui/settings/data/import/rust_import.dart';
import 'package:logging/logging.dart';

final _logger = Logger('PlainTextImportParser');

List<Code> parsePlainTextImport(String content) {
  return runRustImport(() {
    final batch = rust.parsePlainText(content: content);
    for (var index = 0; index < batch.skipped; index++) {
      _logger.warning(
        'Skipping malformed import entry (FormatException)',
        null,
        StackTrace.current,
      );
    }
    return importCodes(batch);
  });
}

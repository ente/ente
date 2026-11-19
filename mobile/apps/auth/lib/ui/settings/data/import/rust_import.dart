import 'package:ente_auth/core/errors.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/models/code_display.dart';
import 'package:ente_auth/src/rust/api/import_api.dart' as rust;
import 'package:ente_auth/ui/settings/data/import/import_flow.dart';
import 'package:logging/logging.dart';

List<Code> importCodes(
  rust.ImportBatch batch, {
  Logger? logger,
  String source = 'import',
}) {
  if (batch.skipped > 0) {
    logger?.warning('Skipped ${batch.skipped} malformed $source entries');
  }
  return batch.codes.map(importCode).toList(growable: false);
}

Code importCode(rust.ImportedCode imported) {
  final display = imported.display;
  return Code.fromOTPAuthUrl(
    imported.uri,
    display: display == null
        ? null
        : CodeDisplay(
            pinned: display.pinned,
            trashed: display.trashed,
            lastUsedAt: display.lastUsedAt,
            tapCount: display.tapCount,
            tags: display.tags,
            note: display.note,
            position: display.position,
            iconSrc: display.iconSrc,
            iconID: display.iconId,
          ),
  );
}

T runRustImport<T>(T Function() operation) {
  try {
    return operation();
  } on rust.ImportError catch (error) {
    _throwImportError(error);
  }
}

Future<T> runRustImportAsync<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } on rust.ImportError catch (error) {
    _throwImportError(error);
  }
}

Never _throwImportError(rust.ImportError error) {
  switch (error) {
    case rust.ImportError_Invalid(:final message, :final entry):
      if (entry != null) {
        throw ImportEntryParseException(entry: entry, error: message);
      }
      throw FormatException(message);
    case rust.ImportError_PasswordRequired():
    case rust.ImportError_IncorrectPassword():
      throw error;
    case rust.ImportError_FileTooLarge(:final maxBytes):
      throw ImportFileTooLargeException(maxBytes.toInt());
  }
}

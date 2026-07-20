import 'dart:convert';

import 'package:ente_auth/models/code.dart';
import 'package:logging/logging.dart';

final _logger = Logger('PlainTextImportParser');

List<Code> parsePlainTextImport(String content) {
  final trimmedContent = content.trim();
  if (trimmedContent.startsWith('otpauth://')) {
    return _parseOTPAuthCodes(trimmedContent);
  }

  final decoded = jsonDecode(trimmedContent);
  if (decoded is! Map || decoded['items'] is! List) {
    throw const FormatException('Expected an export object containing items');
  }

  return _parseEntries(
    (decoded['items'] as List).whereType<Map>(),
    Code.fromExportJson,
  );
}

List<Code> _parseOTPAuthCodes(String content) {
  final entries = content.contains(',')
      ? content.split(',')
      : const LineSplitter().convert(content);
  return _parseEntries(
    entries.map((entry) => entry.trim()).where((entry) => entry.isNotEmpty),
    Code.fromOTPAuthUrl,
  );
}

List<Code> _parseEntries<T>(Iterable<T> entries, Code Function(T entry) parse) {
  final codes = <Code>[];
  for (final entry in entries) {
    try {
      codes.add(parse(entry));
    } catch (error, stackTrace) {
      // Match the import UI's existing behavior: preserve valid entries when
      // one entry in a multi-code export is malformed.
      _logger.severe('Could not parse import entry', error, stackTrace);
    }
  }
  return codes;
}

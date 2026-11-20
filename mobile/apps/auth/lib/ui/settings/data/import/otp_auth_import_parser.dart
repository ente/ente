import 'dart:typed_data';

import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/src/rust/api/import_api.dart' as rust;
import 'package:ente_auth/ui/settings/data/import/rust_import.dart';

const otpAuthImportMaxBytes = 10 * 1024 * 1024;

Future<List<Code>> importOtpAuthExport(
  Uint8List input, {
  required String password,
}) async {
  return runRustImportAsync(
    () async =>
        importCodes(await rust.importOtpAuth(input: input, password: password)),
  );
}

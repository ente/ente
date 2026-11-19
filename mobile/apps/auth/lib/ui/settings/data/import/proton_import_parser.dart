import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/src/rust/api/import_api.dart' as rust;
import 'package:ente_auth/ui/settings/data/import/rust_import.dart';

Future<List<Code>> importProtonExport(String input, {String? password}) async {
  return runRustImportAsync(
    () async =>
        importCodes(await rust.importProton(input: input, password: password)),
  );
}

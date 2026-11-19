import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/src/rust/api/import_api.dart' as rust;
import 'package:ente_auth/ui/settings/data/import/rust_import.dart';

Future<List<Code>> importOpenAuthenticatorExport(
  String input, {
  required String password,
}) async {
  return runRustImportAsync(
    () async => importCodes(
      await rust.importOpenAuthenticator(input: input, password: password),
    ),
  );
}

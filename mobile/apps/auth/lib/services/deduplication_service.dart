import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:logging/logging.dart';

class DeduplicationService {
  final _logger = Logger("DeduplicationService");

  DeduplicationService._privateConstructor();

  static final DeduplicationService instance =
      DeduplicationService._privateConstructor();

  Future<List<DuplicateCodes>> getDuplicateCodes() async {
    try {
      final List<DuplicateCodes> result = await _getDuplicateCodes();
      return result;
    } catch (e, s) {
      _logger.severe("failed to get dedupeCode", e, s);
      rethrow;
    }
  }

  Future<List<DuplicateCodes>> _getDuplicateCodes() async {
    final codes = await CodeStore.instance.getAllCodes();
    final List<DuplicateCodes> duplicateCodes = [];
    Map<String, List<Code>> uniqueCodes = {};

    for (final code in codes) {
      if (code.hasError || code.isTrashed) continue;

      final uniqueKey = "${code.secret}_${code.issuer}_${code.account}";

      if (uniqueCodes.containsKey(uniqueKey)) {
        uniqueCodes[uniqueKey]!.add(code);
      } else {
        uniqueCodes[uniqueKey] = [code];
      }
    }
    for (final key in uniqueCodes.keys) {
      if (uniqueCodes[key]!.length > 1) {
        duplicateCodes.add(DuplicateCodes(key, uniqueCodes[key]!));
      }
    }
    return duplicateCodes;
  }
}

class DuplicateCodes {
  String hash;
  final List<Code> codes;

  DuplicateCodes(this.hash, this.codes);
}

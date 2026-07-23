import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/events/codes_updated_event.dart';
import 'package:ente_auth/models/authenticator/entity_result.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/models/code_parse_error.dart';
import 'package:ente_auth/services/authenticator_service.dart';
import 'package:ente_auth/store/offline_authenticator_db.dart';
import 'package:ente_events/event_bus.dart';
import 'package:logging/logging.dart';

class CodeStore {
  static final CodeStore instance = CodeStore._privateConstructor();

  CodeStore._privateConstructor();

  late AuthenticatorService _authenticatorService;
  final Map<int, Code> _cacheCodes = {};
  final _logger = Logger("CodeStore");

  Future<void> init() async {
    _authenticatorService = AuthenticatorService.instance;
  }

  Future<bool> saveUpadedIndexes(List<Code> codes) async {
    int changedCount = 0;
    final existingAllCodes = await getAllCodes();
    final existingPosition = {};
    for (final code in existingAllCodes) {
      if (code.hasError || code.isTrashed) {
        continue;
      }
      existingPosition[code.generatedID] = code.display.position;
    }
    for (final code in codes) {
      if (code.hasError || code.isTrashed) {
        continue;
      }
      int? oldIndex = existingPosition[code.generatedID];
      if (oldIndex == null) {
        continue;
      }

      int newIndex = codes.indexOf(code);
      if (oldIndex != newIndex) {
        Code updatedCode = code.copyWith(
          display: code.display.copyWith(position: newIndex),
        );
        await addCode(
          updatedCode,
          shouldSync: false,
          existingAllCodes: existingAllCodes,
        );
        changedCount++;
      }
    }
    _logger.info("changedCount index for  $changedCount codes");
    if (changedCount > 0 &&
        _authenticatorService.getAccountMode() == AccountMode.online) {
      _authenticatorService.onlineSync().ignore();
    }

    return true;
  }

  Future<List<Code>> getAllCodes({
    AccountMode? accountMode,
    bool sortCodes = true,
  }) async {
    _cacheCodes.clear();
    final mode = accountMode ?? _authenticatorService.getAccountMode();
    final List<EntityResult> entities = await _authenticatorService.getEntities(
      mode,
    );
    final List<Code> codes = [];

    for (final entity in entities) {
      late Code code;
      try {
        final decodeJson = jsonDecode(entity.rawData);

        if (decodeJson is String && decodeJson.startsWith('otpauth://')) {
          code = Code.fromOTPAuthUrl(decodeJson);
        } else {
          code = Code.fromExportJson(decodeJson);
        }
      } catch (e, s) {
        final parseError = CodeParseError.from(
          error: e,
          storedRawData: entity.rawData,
        );
        code = Code.withError(parseError, entity.rawData);
        _logger.severe("Could not parse code: $parseError", e, s);
      }
      code.generatedID = entity.generatedID;
      code.hasSynced = entity.hasSynced;
      codes.add(code);
      _cacheCodes[code.generatedID!] = code;
    }

    if (sortCodes) {
      codes.sort((firstCode, secondCode) {
        if (secondCode.isPinned && !firstCode.isPinned) return 1;
        if (!secondCode.isPinned && firstCode.isPinned) return -1;

        final issuerComparison = compareAsciiLowerCaseNatural(
          firstCode.issuer,
          secondCode.issuer,
        );
        if (issuerComparison != 0) {
          return issuerComparison;
        }
        return compareAsciiLowerCaseNatural(
          firstCode.account,
          secondCode.account,
        );
      });
    }

    return codes;
  }

  Future<AddResult> addCode(
    Code code, {
    bool shouldSync = true,
    AccountMode? accountMode,
    List<Code>? existingAllCodes,
  }) async {
    final mode = accountMode ?? _authenticatorService.getAccountMode();
    final allCodes = existingAllCodes ?? (await getAllCodes(accountMode: mode));
    bool isExistingCode = false;
    bool hasSameCode = false;

    for (final existingCode in allCodes) {
      if (existingCode.hasError) continue;

      if (code.generatedID != null &&
          existingCode.generatedID == code.generatedID) {
        isExistingCode = true;
        break;
      }
      if (existingCode == code) {
        hasSameCode = true;
      }
    }
    if (!isExistingCode && hasSameCode) {
      return AddResult.duplicate;
    }
    late AddResult result;
    if (isExistingCode) {
      result = AddResult.updateCode;
      await _authenticatorService.updateEntry(
        code.generatedID!,
        code.toOTPAuthUrlFormat(),
        shouldSync,
        mode,
      );
    } else {
      result = AddResult.newCode;
      code.generatedID = await _authenticatorService.addEntry(
        code.toOTPAuthUrlFormat(),
        shouldSync,
        mode,
      );
    }
    Bus.instance.fire(CodesUpdatedEvent());
    return result;
  }

  Future<void> removeCode(Code code, {AccountMode? accountMode}) async {
    final mode = accountMode ?? _authenticatorService.getAccountMode();
    await _authenticatorService.deleteEntry(code.generatedID!, mode);
    Bus.instance.fire(CodesUpdatedEvent());
  }

  bool _isOfflineImportRunning = false;

  Future<void> importOfflineCodes() async {
    if (_isOfflineImportRunning) {
      return;
    }
    _isOfflineImportRunning = true;
    Logger logger = Logger('importOfflineCodes');
    try {
      Configuration config = Configuration.instance;
      if (!config.hasConfiguredAccount() ||
          !config.hasOptedForOfflineMode() ||
          config.getOfflineSecretKey() == null) {
        return;
      }
      logger.info('start import');

      List<Code> offlineCodes = (await CodeStore.instance.getAllCodes(
        accountMode: AccountMode.offline,
      )).where((element) => !element.hasError).toList();
      if (offlineCodes.isEmpty) {
        return;
      }
      bool isOnlineSyncDone = await AuthenticatorService.instance.onlineSync();
      if (!isOnlineSyncDone) {
        logger.info("skip as online sync is not done");
        return;
      }
      final List<Code> onlineCodes = (await CodeStore.instance.getAllCodes(
        accountMode: AccountMode.online,
      )).where((element) => !element.hasError).toList();
      logger.info(
        'importing ${offlineCodes.length} offline codes with ${onlineCodes.length} online codes',
      );
      for (Code eachCode in offlineCodes) {
        bool alreadyPresent = onlineCodes.any(
          (oc) =>
              oc.issuer == eachCode.issuer &&
              oc.account == eachCode.account &&
              oc.secret == eachCode.secret,
        );
        int? generatedID = eachCode.generatedID!;
        logger.info(
          'importingCode: genID ${eachCode.generatedID} & isAlreadyPresent $alreadyPresent',
        );
        if (!alreadyPresent) {
          eachCode.generatedID = null;
          final AddResult result = await CodeStore.instance.addCode(
            eachCode,
            accountMode: AccountMode.online,
            shouldSync: false,
          );
          logger.info(
            'importedCode: genID ${eachCode.generatedID} result: ${result.name}',
          );
        }
        await OfflineAuthenticatorDB.instance.deleteByIDs(
          generatedIDs: [generatedID],
        );
      }
      AuthenticatorService.instance.onlineSync().ignore();
    } catch (e, s) {
      _logger.severe("error while importing offline codes", e, s);
    } finally {
      _isOfflineImportRunning = false;
    }
  }

  Future<String> getCodesForExport() async {
    final allCodes = await getAllCodes(sortCodes: false);
    String data = "";
    for (final code in allCodes) {
      if (code.hasError) continue;
      data += "${code.toOTPAuthUrlFormat()}\n";
    }
    return data;
  }
}

enum AddResult { newCode, duplicate, updateCode }

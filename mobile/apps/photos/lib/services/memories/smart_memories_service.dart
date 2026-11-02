import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:logging/logging.dart";
import "package:photos/locale.dart";
import "package:photos/models/base_location.dart";
import "package:photos/models/memories/memories_cache.dart";
import "package:photos/models/memories/smart_memory.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/language_service.dart";
import "package:photos/services/memories/memories_computer.dart";

class SmartMemoriesService {
  final _logger = Logger("SmartMemoriesService");

  SmartMemoriesService();

  Future<MemoriesResult> calcAllSmartMemories(
    DateTime now,
    MemoriesCache oldCache, {
    required bool mlEnabled,
  }) async {
    try {
      final TimeLogger t = TimeLogger(context: "calcAllSmartMemories");
      final memoriesResult = await memoriesComputer.computeAll(
        now,
        oldCache,
        mlEnabled: mlEnabled,
      );
      final local = await getLocale();
      final languageCode = local?.languageCode ?? "en";
      final s = await LanguageService.locals;
      _logger.info('get locale and S $t');
      return await _finalizeMemoriesResult(memoriesResult, s, languageCode, t);
    } catch (e, s) {
      _logger.severe("Error calculating smart memories", e, s);
      return _fallbackAfterCalculationError();
    }
  }

  Future<({MemoriesResult current, MemoriesResult next})>
  calcCurrentAndNextSmartMemories(
    DateTime current,
    DateTime next,
    MemoriesCache oldCache, {
    required bool mlEnabled,
  }) async {
    try {
      final TimeLogger t = TimeLogger(
        context: "calcCurrentAndNextSmartMemories",
      );
      final results = await memoriesComputer.computeCurrentAndNext(
        current,
        next,
        oldCache,
        mlEnabled: mlEnabled,
      );
      final local = await getLocale();
      final languageCode = local?.languageCode ?? "en";
      final s = await LanguageService.locals;
      _logger.info('get locale and S $t');
      final currentResult = await _finalizeMemoriesResult(
        results.current,
        s,
        languageCode,
        t,
      );
      final nextResult = await _finalizeMemoriesResult(
        results.next,
        s,
        languageCode,
        t,
      );
      return (current: currentResult, next: nextResult);
    } catch (e, s) {
      _logger.severe("Error calculating current and next smart memories", e, s);
      final currentResult = await _fallbackAfterCalculationError();
      if (currentResult.failed) {
        return (current: currentResult, next: MemoriesResult.failed());
      }
      return (
        current: currentResult,
        next: await _fallbackAfterCalculationError(),
      );
    }
  }

  Future<MemoriesResult> _finalizeMemoriesResult(
    MemoriesResult memoriesResult,
    StringsLocalizations s,
    String languageCode,
    TimeLogger t,
  ) async {
    try {
      if (isLocalGalleryMode && memoriesResult.isEmpty) {
        _logger.severe(
          "Smart memories returned empty in local gallery mode, falling back to simple memories",
        );
        final fallbackMemories = await calcSimpleMemories();
        return MemoriesResult(fallbackMemories, <BaseLocation>[]);
      }
      if (memoriesResult.failed) {
        return memoriesResult;
      }
      for (final memory in memoriesResult.memories) {
        memory.title = memory.createTitle(s, languageCode);
      }
      _logger.info('titles created for all memories $t');
      return memoriesResult;
    } catch (e, s) {
      _logger.severe("Error finalizing smart memories", e, s);
      return _fallbackAfterCalculationError();
    }
  }

  Future<MemoriesResult> _fallbackAfterCalculationError() async {
    if (isLocalGalleryMode) {
      try {
        _logger.warning(
          "Falling back to simple memories after smart memories failure in local gallery mode",
        );
        final fallbackMemories = await calcSimpleMemories();
        return MemoriesResult(fallbackMemories, <BaseLocation>[]);
      } catch (fallbackError, fallbackStackTrace) {
        _logger.severe(
          "Offline fallback to simple memories failed",
          fallbackError,
          fallbackStackTrace,
        );
      }
    }
    return MemoriesResult.failed();
  }

  Future<List<SmartMemory>> calcSimpleMemories() async {
    final memories = await memoriesComputer.computeSimple();
    final local = await getLocale();
    final languageCode = local?.languageCode ?? "en";
    final s = await LanguageService.locals;
    _logger.info('get locale and S');
    for (final memory in memories) {
      memory.title = memory.createTitle(s, languageCode);
    }
    return memories;
  }

  static Future<String> getDateFormattedLocale({
    required int creationTime,
  }) async {
    final locale = await getLocale();

    return getDateFormatted(
      creationTime: creationTime,
      languageCode: locale!.languageCode,
    );
  }

  static String getDateFormatted({
    required int creationTime,
    BuildContext? context,
    String? languageCode,
  }) {
    return DateFormat.yMMMd(
      context != null
          ? Localizations.localeOf(context).languageCode
          : languageCode ?? "en",
    ).format(DateTime.fromMicrosecondsSinceEpoch(creationTime));
  }
}

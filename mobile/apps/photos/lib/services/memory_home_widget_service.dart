import 'dart:math';
import "package:collection/collection.dart";
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:logging/logging.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/memories/smart_memory.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/home_widget_service.dart';
import 'package:photos/services/sync/local_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryHomeWidgetService {
  // Constants
  static const String SELECTED_LAST_YEAR_MEMORIES_KEY =
      "selectedLastYearMemoriesHW";
  static const String SELECTED_ML_MEMORIES_KEY = "selectedMLMemoriesHW";
  static const String SELECTED_ON_THIS_DAY_MEMORIES_KEY =
      "selectedOnThisDayMemoriesHW";
  static const String ANDROID_CLASS_NAME = "EnteMemoryWidgetProvider";
  static const String IOS_CLASS_NAME = "EnteMemoryWidget";
  static const String MEMORY_STATUS_KEY = "memoryStatusKey.widget";
  static const String MEMORY_CHANGED_KEY = "memoryChanged.widget";
  static const String TOTAL_MEMORIES_KEY = "totalMemories";
  static const int MAX_MEMORIES_LIMIT = 50;

  // Singleton pattern
  static final MemoryHomeWidgetService instance =
      MemoryHomeWidgetService._privateConstructor();
  MemoryHomeWidgetService._privateConstructor();

  // Properties
  final Logger _logger = Logger((MemoryHomeWidgetService).toString());
  SharedPreferences get _prefs => ServiceLocator.instance.prefs;

  // Preference getters and setters
  bool? hasLastYearMemoriesSelected() {
    return _prefs.getBool(SELECTED_LAST_YEAR_MEMORIES_KEY);
  }

  Future<void> setLastYearMemoriesSelected(bool selectedMemories) async {
    await _prefs.setBool(SELECTED_LAST_YEAR_MEMORIES_KEY, selectedMemories);
  }

  bool? getMLMemoriesSelected() {
    return _prefs.getBool(SELECTED_ML_MEMORIES_KEY);
  }

  Future<void> setSelectedMLMemories(bool selectedMemories) async {
    await _prefs.setBool(SELECTED_ML_MEMORIES_KEY, selectedMemories);
  }

  bool? getOnThisDayMemoriesSelected() {
    return _prefs.getBool(SELECTED_ON_THIS_DAY_MEMORIES_KEY);
  }

  Future<void> setOnThisDayMemoriesSelected(bool selectedMemories) async {
    await _prefs.setBool(SELECTED_ON_THIS_DAY_MEMORIES_KEY, selectedMemories);
  }

  // Public methods
  Future<void> initMemoryHomeWidget() async {
    await HomeWidgetService.instance.computeLock.synchronized(() async {
      if (await _hasAnyBlockers()) {
        await clearWidget();
        return;
      }

      _logger.info("Initializing memories widget");

      final bool forceFetchNewMemories = await _shouldUpdateWidgetCache();

      if (forceFetchNewMemories) {
        if (await _updateMemoriesWidgetCache()) {
          await updateMemoryChanged(false);
          _logger.info("Force fetch new memories complete");
        }
      } else {
        await _refreshMemoriesWidget();
        _logger.info("Refresh memories widget complete");
      }
    });
  }

  Future<void> clearWidget() async {
    if (getMemoriesStatus() == WidgetStatus.syncedEmpty) {
      _logger.info("Widget already empty, nothing to clear");
      return;
    }

    await _setTotalMemories(null);
    await updateMemoriesStatus(WidgetStatus.syncedEmpty);
    await _refreshWidget(message: "MemoryHomeWidget cleared & updated");
  }

  bool isMemoryChanged() {
    return _prefs.getBool(MEMORY_CHANGED_KEY) ?? false;
  }

  Future<void> updateMemoryChanged(bool value) async {
    _logger.info("Updating memory changed flag to $value");
    await _prefs.setBool(MEMORY_CHANGED_KEY, value);
  }

  WidgetStatus getMemoriesStatus() {
    return WidgetStatus.values.firstWhereOrNull(
          (v) => v.index == (_prefs.getInt(MEMORY_STATUS_KEY) ?? 0),
        ) ??
        WidgetStatus.notSynced;
  }

  Future<void> updateMemoriesStatus(WidgetStatus value) async {
    await _prefs.setInt(MEMORY_STATUS_KEY, value.index);
  }

  Future<void> checkPendingMemorySync() async {
    if (await _hasAnyBlockers()) {
      await clearWidget();
      return;
    }

    _logger.info("Checking pending memory sync");
    if (await _shouldUpdateWidgetCache()) {
      await initMemoryHomeWidget();
    }
  }

  Future<void> memoryChanged() async {
    await updateMemoryChanged(true);

    final cachedMemories = await _getMemoriesForWidget();
    if (cachedMemories.isEmpty) {
      _logger.info("Memories empty, no update needed");
      await updateMemoryChanged(false);
      await clearWidget();
      return;
    }

    _logger.info("Memories changed, updating widget");
    await initMemoryHomeWidget();
  }

  Future<int> countHomeWidgets() async {
    return await HomeWidgetService.instance.countHomeWidgets(
      ANDROID_CLASS_NAME,
      IOS_CLASS_NAME,
    );
  }

  Future<void> onLaunchFromWidget(int generatedId) async {
    memoriesCacheService.goToMemoryFromGeneratedFileID(generatedId).ignore();
    await _refreshMemoriesWidget();
  }

  // Private methods
  Future<bool> _hasAnyBlockers() async {
    // Check if first import is completed
    final hasCompletedFirstImport = LocalSyncService.instance
        .hasCompletedFirstImportOrBypassed();
    if (!hasCompletedFirstImport) {
      return true;
    }

    // Check if memories are enabled
    final areMemoriesShown = memoriesCacheService.showAnyMemories;
    if (!areMemoriesShown) {
      return true;
    }

    return false;
  }

  Future<void> _refreshMemoriesWidget() async {
    // only refresh if widget was synced without issues
    if (await countHomeWidgets() == 0) return;
    await _refreshWidget(message: "Refreshing from existing memory set");
  }

  Future<bool> _shouldUpdateWidgetCache() async {
    // Update widget cache when memories were changed
    if (isMemoryChanged() == true) return true;

    final memoriesStatus = getMemoriesStatus();

    // update widget cache if
    // - memories not synced
    // - memories synced partially but now home widget is present
    return memoriesStatus == WidgetStatus.notSynced ||
        memoriesStatus == WidgetStatus.syncedPartially &&
            await countHomeWidgets() > 0;
  }

  Future<List<SmartMemory>> _getMemoriesForWidget() async {
    final isMLEnabled = hasGrantedMLConsent;
    bool? smartMemoryValue = getMLMemoriesSelected();
    bool? lastYearValue = hasLastYearMemoriesSelected();
    bool? onThisDayValue = getOnThisDayMemoriesSelected();

    // If ML is enabled then we use Smart memories by default, otherwise date based memories
    if (isMLEnabled) {
      lastYearValue ??= false;
      onThisDayValue ??= false;
      smartMemoryValue ??= true;
    } else {
      lastYearValue ??= true;
      onThisDayValue ??= true;
      smartMemoryValue ??= false;
    }

    // TODO: Only read from cache memory
    final memories = await memoriesCacheService.getMemoriesForWidget(
      onThisDay: onThisDayValue,
      pastYears: lastYearValue,
      smart: smartMemoryValue,
      hasAnyWidgets: await countHomeWidgets() > 0,
    );

    return memories;
  }

  Future<Map<String, Iterable<EnteFile>>> _getMemoriesWithFiles() async {
    final memories = await _getMemoriesForWidget();

    if (memories.isEmpty) {
      return {};
    }

    return Map.fromEntries(
      memories.map(
        (memory) =>
            MapEntry(memory.title, memory.memories.map((m) => m.file).toList()),
      ),
    );
  }

  Future<void> _refreshWidget({String? message}) async {
    await HomeWidgetService.instance.updateWidget(
      androidClass: ANDROID_CLASS_NAME,
      iOSClass: IOS_CLASS_NAME,
    );

    if (flagService.internalUser) {
      await Fluttertoast.showToast(
        msg: "[i][mem] ${message ?? "MemoryHomeWidget updated"}",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        timeInSecForIosWeb: 1,
        backgroundColor: Colors.black,
        textColor: Colors.white,
        fontSize: 16.0,
      );
    }

    _logger.info("Home Widget updated: ${message ?? "standard update"}");
  }

  Future<void> _setTotalMemories(int? total) async {
    await HomeWidgetService.instance.setData(TOTAL_MEMORIES_KEY, total);
  }

  // _updateMemoriesWidgetCache will return false if no memories were cached
  Future<bool> _updateMemoriesWidgetCache() async {
    // TODO: Can update the method to fetch directly max limit random memories
    final memoriesWithFiles = await _getMemoriesWithFiles();
    if (memoriesWithFiles.isEmpty) {
      await clearWidget();
      return false;
    }

    final bool isWidgetPresent = await countHomeWidgets() > 0;
    final limit = isWidgetPresent
        ? HomeWidgetService.instance.getWidgetImageLimit()
        : HomeWidgetService.WIDGET_IMAGE_LIMIT_MINIMAL;
    final maxAttempts = limit * 10;

    int renderedCount = 0;
    int attemptsCount = 0;

    await updateMemoriesStatus(WidgetStatus.notSynced);

    final memoriesWithFilesLength = memoriesWithFiles.length;
    final memoriesWithFilesEntries = memoriesWithFiles.entries.toList();
    final random = Random();

    while (renderedCount < limit && attemptsCount < maxAttempts) {
      final randomEntry =
          memoriesWithFilesEntries[random.nextInt(memoriesWithFilesLength)];

      if (randomEntry.value.isEmpty) continue;

      final randomMemoryFile = randomEntry.value.elementAt(
        random.nextInt(randomEntry.value.length),
      );
      final memoryTitle = randomEntry.key;

      final renderResult = await HomeWidgetService.instance
          .renderFile(
            randomMemoryFile,
            "memory_widget_$renderedCount",
            memoryTitle,
            null,
          )
          .catchError((e, stackTrace) {
            _logger.severe("Error rendering widget", e, stackTrace);
            return null;
          });

      if (renderResult != null) {
        // Check for blockers again before continuing
        if (await _hasAnyBlockers()) {
          await clearWidget();
          return true;
        }

        await _setTotalMemories(renderedCount);

        // Show update toast after first item is rendered
        if (renderedCount == 1) {
          await _refreshWidget(
            message: "First memory fetched, updating widget",
          );
          await updateMemoriesStatus(WidgetStatus.syncedPartially);
        }

        renderedCount++;
      }

      attemptsCount++;
    }

    if (attemptsCount >= maxAttempts) {
      _logger.warning(
        "Hit max attempts $maxAttempts. Only rendered $renderedCount of limit $limit.",
      );
    }

    if (renderedCount == 0) {
      return false;
    }

    if (isWidgetPresent) {
      await updateMemoriesStatus(WidgetStatus.syncedAll);
    }

    await _refreshWidget(
      message: "Switched to next memory set, total: $renderedCount",
    );
    return true;
  }
}

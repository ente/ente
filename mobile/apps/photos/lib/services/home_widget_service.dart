import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart' as hw;
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_foundation/path_provider_foundation.dart';
import 'package:photos/core/constants.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/module/download/thumbnail.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/album_home_widget_service.dart';
import 'package:photos/services/app_navigation_service.dart';
import 'package:photos/services/memory_home_widget_service.dart';
import 'package:photos/services/people_home_widget_service.dart';
import 'package:photos/services/smart_memories_service.dart';
import 'package:photos/ui/settings/ml/machine_learning_settings_page.dart';
import 'package:photos/ui/settings/widgets/albums_widget_settings.dart';
import 'package:photos/ui/settings/widgets/memories_widget_settings.dart';
import 'package:photos/ui/settings/widgets/people_widget_settings.dart';
import 'package:synchronized/synchronized.dart';

enum WidgetStatus {
  notSynced,
  // Some data was cached before the sync stopped or without a widget installed.
  syncedPartially,
  // A widget that previously had data was deliberately cleared.
  syncedEmpty,
  syncedAll,
}

class HomeWidgetService {
  static const double THUMBNAIL_SIZE = 512.0;
  static const String WIDGET_DIRECTORY = 'home_widget';
  static const int WIDGET_IMAGE_LIMIT_V1 = 50;
  static const int WIDGET_IMAGE_LIMIT_MINIMAL = 5;

  static const String MEMORY_WIDGET_SCHEME = 'memorywidget';
  static const String PEOPLE_WIDGET_SCHEME = 'peoplewidget';
  static const String ALBUM_WIDGET_SCHEME = 'albumwidget';

  static const String GENERATED_ID_PARAM = 'generatedId';
  static const String MAIN_KEY_PARAM = 'mainKey';

  static const String DATA_SUFFIX = '_data';
  static const String UPLOADED_FILE_ID_KEY = 'uploadedFileID';
  static const String WIDGET_HIDE_TITLE_FLAGS_KEY = 'widgetHideTitleFlags';

  static final HomeWidgetService instance =
      HomeWidgetService._privateConstructor();
  HomeWidgetService._privateConstructor();

  final Logger _logger = Logger((HomeWidgetService).toString());
  final computeLock = Lock();
  bool _isAppGroupSet = false;

  Future<void> setAppGroup({String id = iOSGroupIDMemory}) async {
    if (!Platform.isIOS || _isAppGroupSet) return;
    _logger.info("Setting app group id");
    await hw.HomeWidget.setAppGroupId(id).catchError((error) {
      _logger.severe("Failed to set app group ID: $error");
      return null;
    });
    _isAppGroupSet = true;
  }

  int getWidgetImageLimit() {
    return WIDGET_IMAGE_LIMIT_V1;
  }

  Future<void> initHomeWidget([bool isBg = false]) async {
    await setAppGroup();
    await AlbumHomeWidgetService.instance.initAlbumHomeWidget(isBg);
    await PeopleHomeWidgetService.instance.initPeopleHomeWidget();
    await MemoryHomeWidgetService.instance.initMemoryHomeWidget();
  }

  Future<bool?> updateWidget({
    required String androidClass,
    required String iOSClass,
  }) async {
    return await hw.HomeWidget.updateWidget(
      name: androidClass,
      androidName: androidClass,
      qualifiedAndroidName: 'io.ente.photos.$androidClass',
      iOSName: iOSClass,
    );
  }

  Future<T?> getData<T>(String key) async {
    return hw.HomeWidget.getWidgetData<T>(key);
  }

  Future<bool?> setData<T>(String key, T? data) async {
    return hw.HomeWidget.saveWidgetData<T>(key, data);
  }

  Future<Size?> renderFile(
    EnteFile file,
    String key,
    String title,
    String? mainKey, {
    int? uploadedFileID,
  }) async {
    final result = await _captureFileLegacy(
      file,
      key,
      title,
      mainKey,
      uploadedFileID,
    );
    if (!result) {
      _logger.warning("Failed to capture file ${file.displayName}");
      return null;
    }

    return const Size(THUMBNAIL_SIZE, THUMBNAIL_SIZE);
  }

  Future<int> countHomeWidgets(String androidClass, String iOSClass) async {
    final installedWidgets = await getInstalledWidgets();
    final relevantWidgets = installedWidgets
        .where(
          (widget) =>
              (widget.androidClassName?.contains(androidClass) ?? false) ||
              widget.iOSKind == iOSClass,
        )
        .toList();

    return relevantWidgets.length;
  }

  Future<List<hw.HomeWidgetInfo>> getInstalledWidgets() async {
    return await hw.HomeWidget.getInstalledWidgets();
  }

  Future<bool> _captureFileLegacy(
    EnteFile file,
    String key,
    String title,
    String? mainKey,
    int? uploadedFileID,
  ) async {
    try {
      final thumbnail = await getThumbnail(file);
      if (thumbnail == null) {
        _logger.warning("Failed to get thumbnail for file ${file.displayName}");
        return false;
      }

      final String widgetDirectory = await _getWidgetStorageDirectory();

      final String thumbnailPath =
          '$widgetDirectory/$WIDGET_DIRECTORY/$key.png';
      final File thumbnailFile = File(thumbnailPath);

      if (!await thumbnailFile.exists()) {
        await thumbnailFile.create(recursive: true);
      }

      await thumbnailFile.writeAsBytes(thumbnail);
      await setData(key, thumbnailPath);

      final subText = await SmartMemoriesService.getDateFormattedLocale(
        creationTime: file.creationTime!,
      );

      final Map<String, dynamic> metadata = {
        "title": title,
        "subText": subText,
        "generatedId": file.generatedID!,
        "mainKey": ?mainKey,
        UPLOADED_FILE_ID_KEY: ?uploadedFileID,
      };

      await _saveWidgetMetadata(key, metadata);

      return true;
    } catch (error, stackTrace) {
      _logger.severe("Failed to save the thumbnail", error, stackTrace);
      return false;
    }
  }

  Future<void> _saveWidgetMetadata(
    String key,
    Map<String, dynamic> metadata,
  ) async {
    final String dataKey = key + DATA_SUFFIX;

    // iOS stores maps directly; Android expects a JSON string.
    if (Platform.isIOS) {
      await hw.HomeWidget.saveWidgetData<Map<String, dynamic>>(
        dataKey,
        metadata,
      );
    } else {
      await hw.HomeWidget.saveWidgetData<String>(dataKey, jsonEncode(metadata));
    }
  }

  Future<String> _getWidgetStorageDirectory() async {
    if (Platform.isIOS) {
      final PathProviderFoundation provider = PathProviderFoundation();
      return (await provider.getContainerPath(
        appGroupIdentifier: iOSGroupIDMemory,
      ))!;
    } else {
      return (await getApplicationSupportDirectory()).path;
    }
  }

  Future<void> clearWidget(bool autoLogout) async {
    if (autoLogout) {
      await setAppGroup();
    }

    await Future.wait([
      AlbumHomeWidgetService.instance.clearWidget(),
      PeopleHomeWidgetService.instance.clearWidget(),
      MemoryHomeWidgetService.instance.clearWidget(),
      hw.HomeWidget.saveWidgetData<int?>(WIDGET_HIDE_TITLE_FLAGS_KEY, null),
    ]);

    try {
      final String widgetParent = await _getWidgetStorageDirectory();
      final String widgetPath = '$widgetParent/$WIDGET_DIRECTORY';
      final dir = Directory(widgetPath);

      await dir.delete(recursive: true);
      _logger.info("Widget directory cleared successfully");
    } catch (e) {
      _logger.severe("Failed to clear widget directory", e);
    }
  }

  Future<void> onLaunchFromWidget(Uri? uri) async {
    if (uri == null) {
      _logger.warning("Widget launch failed: URI is null");
      return;
    }

    _logger.info("Handling widget launch with URI: $uri");

    final generatedId = int.tryParse(
      uri.queryParameters[GENERATED_ID_PARAM] ?? "",
    );

    final bool isConfigureRoute =
        uri.host == 'configure' || generatedId == null;

    switch (uri.scheme) {
      case MEMORY_WIDGET_SCHEME:
        if (isConfigureRoute) {
          _logger.info("Navigating to Memories widget customization screen");
          await AppNavigationService.instance.pushPage(
            const MemoriesWidgetSettings(),
          );
        } else {
          await MemoryHomeWidgetService.instance.onLaunchFromWidget(
            generatedId,
          );
        }
        break;

      case PEOPLE_WIDGET_SCHEME:
        if (isConfigureRoute) {
          _logger.info("Navigating to People widget customization screen");
          if (!hasGrantedMLConsent) {
            await AppNavigationService.instance.pushPage(
              const MachineLearningSettingsPage(),
              forceCustomPageRoute: true,
            );
          } else {
            await AppNavigationService.instance.pushPage(
              const PeopleWidgetSettings(),
            );
          }
        } else {
          final personId = uri.queryParameters[MAIN_KEY_PARAM] ?? "";
          await PeopleHomeWidgetService.instance.onLaunchFromWidget(
            generatedId,
            personId,
          );
        }
        break;

      case ALBUM_WIDGET_SCHEME:
        if (isConfigureRoute) {
          _logger.info("Navigating to Album widget customization screen");
          await AppNavigationService.instance.pushPage(
            const AlbumsWidgetSettings(),
          );
        } else {
          final collectionId = int.tryParse(
            uri.queryParameters[MAIN_KEY_PARAM] ?? "",
          );
          if (collectionId == null) {
            _logger.warning(
              "Album widget launch failed: Invalid or missing collection ID",
            );
            return;
          }

          await AlbumHomeWidgetService.instance.onLaunchFromWidget(
            generatedId,
            collectionId,
          );
        }
        break;

      default:
        _logger.warning(
          "Widget launch failed: Unknown widget scheme '${uri.scheme}'",
        );
        break;
    }
  }
}

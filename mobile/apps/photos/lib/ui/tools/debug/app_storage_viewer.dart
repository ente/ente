import 'dart:io';

import 'package:ente_components/ente_components.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import "package:logging/logging.dart";
import 'package:path_provider/path_provider.dart';
import 'package:photos/core/cache/video_cache_manager.dart';
import 'package:photos/core/configuration.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/service_locator.dart";
import 'package:photos/ui/settings/components/settings_page_scaffold.dart';
import 'package:photos/ui/tools/debug/path_storage_viewer.dart';

class AppStorageViewer extends StatefulWidget {
  const AppStorageViewer({super.key});

  @override
  State<AppStorageViewer> createState() => _AppStorageViewerState();
}

class _AppStorageViewerState extends State<AppStorageViewer> {
  final List<PathStorageItem> paths = [];
  late String iosTempDirectoryPath;
  late bool internalUser;
  int _refreshCounterKey = 0;
  final Logger _logger = Logger("_AppStorageViewerState");

  @override
  void initState() {
    super.initState();
    internalUser = flagService.internalUser;
    addPath();
  }

  void addPath() async {
    final appDocumentsDirectory = (await getApplicationDocumentsDirectory());
    final appSupportDirectory = (await getApplicationSupportDirectory());
    final appTemporaryDirectory = (await getTemporaryDirectory());
    iosTempDirectoryPath = "${appDocumentsDirectory.parent.path}/tmp/";
    final iOSPhotoManagerInAppCacheDirectory =
        iosTempDirectoryPath + "flutter-images";
    final androidGlideCacheDirectory =
        "${appTemporaryDirectory.path}/image_manager_disk_cache/";

    final String tempDownload = Configuration.instance.getTempDirectory();
    final String personFaceThumbnails = Configuration.instance
        .getPersonFaceThumbnailCacheDirectory();
    final String cacheDirectory = Configuration.instance
        .getThumbnailCacheDirectory();
    final imageCachePath =
        appTemporaryDirectory.path + "/" + DefaultCacheManager.key;
    final videoCachePath =
        appTemporaryDirectory.path + "/" + VideoCacheManager.key;
    if (!mounted) return;
    paths.addAll([
      PathStorageItem.name(
        imageCachePath,
        AppLocalizations.of(context).remoteImages,
        allowCacheClear: true,
      ),
      PathStorageItem.name(
        videoCachePath,
        AppLocalizations.of(context).remoteVideos,
        allowCacheClear: true,
      ),
      PathStorageItem.name(
        cacheDirectory,
        AppLocalizations.of(context).remoteThumbnails,
        allowCacheClear: true,
      ),
      PathStorageItem.name(
        tempDownload,
        AppLocalizations.of(context).pendingSync,
      ),
      PathStorageItem.name(
        Platform.isAndroid
            ? androidGlideCacheDirectory
            : iOSPhotoManagerInAppCacheDirectory,
        AppLocalizations.of(context).localGallery,
        allowCacheClear: true,
      ),
    ]);
    final List<String> directoryStatePath = [
      appDocumentsDirectory.path,
      appSupportDirectory.path,
      appTemporaryDirectory.path,
    ];
    if (!Platform.isAndroid) {
      directoryStatePath.add(iosTempDirectoryPath);
    }
    if (internalUser) {
      paths.addAll([
        PathStorageItem.name(appDocumentsDirectory.path, "Documents"),
        PathStorageItem.name(appSupportDirectory.path, "Support"),
        PathStorageItem.name(appTemporaryDirectory.path, "Temp"),
        PathStorageItem.name(
          personFaceThumbnails,
          "Face thumbnails",
          allowCacheClear: true,
        ),
      ]);
      if (!Platform.isAndroid) {
        paths.add(PathStorageItem.name(iosTempDirectoryPath, "/tmp"));
      }
    }
    prettyStringDirectoryStats(directoryStatePath).ignore();
    if (mounted) {
      setState(() => {});
    }
  }

  Future<void> prettyStringDirectoryStats(List<String> paths) async {
    try {
      for (var path in paths) {
        final DirectoryStat stat = await getDirectoryStat(Directory(path));
        final content = prettyPrintDirectoryStat(stat, path);
        if (content.isNotEmpty) {
          _logger.info(content);
        }
      }
    } catch (e) {
      _logger.severe("Failed to print directory stats", e);
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("$runtimeType building");

    return SettingsPageScaffold(
      title: AppLocalizations.of(context).manageDeviceStorage,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: Spacing.lg,
            top: Spacing.md,
            bottom: Spacing.sm,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              AppLocalizations.of(context).cachedData,
              style: TextStyles.mini.copyWith(
                color: context.componentColors.textLight,
              ),
            ),
          ),
        ),
        MenuGroupComponent(
          items: [
            for (var index = 0; index < paths.length; index++)
              PathStorageViewer(
                paths[index],
                enableDoubleTapClear: internalUser,
                key: ValueKey("$index-$_refreshCounterKey"),
              ),
          ],
        ),
        const SizedBox(height: Spacing.xl),
        ButtonComponent(
          label: AppLocalizations.of(context).clearCaches,
          variant: ButtonComponentVariant.neutral,
          onTap: () async {
            for (var pathItem in paths) {
              if (pathItem.allowCacheClear) {
                await deleteDirectoryContents(pathItem.path);
              }
            }
            if (!Platform.isAndroid) {
              await deleteDirectoryContents(iosTempDirectoryPath);
            }
            // Small delay to allow file system to sync
            await Future.delayed(const Duration(milliseconds: 300));
            _refreshCounterKey++;
            if (mounted) {
              setState(() => {});
            }
          },
        ),
        const SizedBox(height: Spacing.xl),
      ],
    );
  }
}

import "dart:async";
import "dart:math";
import "dart:typed_data";

import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:photos/core/cache/thumbnail_in_memory_cache.dart';
import 'package:photos/core/constants.dart';
import 'package:photos/core/errors.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/core/exceptions.dart';
import 'package:photos/db/files_db.dart';
import 'package:photos/db/trash_db.dart';
import 'package:photos/events/files_updated_event.dart';
import 'package:photos/events/local_photos_updated_event.dart';
import 'package:photos/models/api/collection/user.dart';
import 'package:photos/models/file/extensions/file_props.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import 'package:photos/models/file/trash_file.dart';
import 'package:photos/models/gallery_type.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/collections_service.dart';
import 'package:photos/services/favorites_service.dart';
import "package:photos/ui/sharing/user_avator_widget.dart";
import 'package:photos/ui/viewer/file/file_icons_widget.dart';
import 'package:photos/ui/viewer/gallery/component/group/type.dart';
import 'package:photos/ui/viewer/gallery/state/gallery_context_state.dart';
import 'package:photos/utils/file_util.dart';
import 'package:photos/utils/thumbnail_util.dart';

class ThumbnailWidget extends StatefulWidget {
  final EnteFile file;
  final BoxFit fit;

  /// Returns ThumbnailWidget without any overlay icons if true.
  final bool rawThumbnail;
  final bool shouldShowSyncStatus;
  final bool showFavForAlbumOnly;
  final bool shouldShowLivePhotoOverlay;
  final Duration? diskLoadDeferDuration;
  final Duration? serverLoadDeferDuration;
  final int thumbnailSize;
  final bool useRequestedThumbnailSizeForLocalCache;
  final bool shouldShowOwnerAvatar;
  final AvatarType ownerAvatarType;
  final bool shouldShowFavoriteIcon;
  final Color? placeholderColor;

  ///On video thumbnails, shows the video duration if true. If false,
  ///shows a centered play icon.
  final bool shouldShowVideoDuration;
  final bool shouldShowVideoOverlayIcon;

  ThumbnailWidget(
    this.file, {
    Key? key,
    this.fit = BoxFit.cover,
    this.rawThumbnail = false,
    this.shouldShowSyncStatus = true,
    this.shouldShowLivePhotoOverlay = false,
    this.showFavForAlbumOnly = false,
    this.shouldShowOwnerAvatar = false,
    this.ownerAvatarType = AvatarType.small,
    this.diskLoadDeferDuration,
    this.serverLoadDeferDuration,
    this.thumbnailSize = thumbnailSmallSize,
    this.useRequestedThumbnailSizeForLocalCache = false,
    this.shouldShowFavoriteIcon = true,
    this.placeholderColor,
    this.shouldShowVideoDuration = false,
    this.shouldShowVideoOverlayIcon = true,
  }) : super(key: key ?? Key(file.tag));

  @override
  State<ThumbnailWidget> createState() => _ThumbnailWidgetState();
}

class _ThumbnailWidgetState extends State<ThumbnailWidget> {
  static final _logger = Logger("ThumbnailWidget");
  bool _hasLoadedThumbnail = false;
  bool _isLoadingLocalThumbnail = false;
  bool _errorLoadingLocalThumbnail = false;
  bool _isLoadingRemoteThumbnail = false;
  bool _errorLoadingRemoteThumbnail = false;
  ImageProvider? _imageProvider;
  int? optimizedImageHeight;
  int? optimizedImageWidth;
  String? _localThumbnailQueueTaskId;
  static const _maxLocalThumbnailRetries = 8;

  int get _localCacheThumbnailSize {
    if (widget.useRequestedThumbnailSizeForLocalCache) {
      return widget.thumbnailSize;
    }
    return thumbnailSmallSize;
  }

  @override
  void initState() {
    super.initState();
    assignOptimizedImageDimensions();
  }

  @override
  void dispose() {
    super.dispose();
    Future.delayed(const Duration(milliseconds: 10), () {
      if (!mounted && _localThumbnailQueueTaskId != null) {
        if (widget.thumbnailSize == thumbnailLargeSize) {
          largeLocalThumbnailQueue.removeTask(_localThumbnailQueueTaskId!);
        } else if (widget.thumbnailSize == thumbnailSmallSize) {
          smallLocalThumbnailQueue.removeTask(_localThumbnailQueueTaskId!);
        }
      }
      // Cancel request only if the widget has been unmounted
      if (!mounted && widget.file.isRemoteOnlyFile && !_hasLoadedThumbnail) {
        removePendingGetThumbnailRequestIfAny(widget.file);
      }
    });
  }

  @override
  void didUpdateWidget(ThumbnailWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.file.generatedID != oldWidget.file.generatedID) {
      _reset();
    }
  }

  static final TaskQueue<String> smallLocalThumbnailQueue = _initSmallQueue();
  static final TaskQueue<String> largeLocalThumbnailQueue = _initLargeQueue();

  static TaskQueue<String> _initSmallQueue() {
    final maxConcurrent = flagService.internalUser ? 45 : 15;
    const timeoutSeconds = 60;
    const maxSize = 200;

    _logger.info(
      "Initializing Small Local Thumbnail Queue - "
      "MaxConcurrent: $maxConcurrent, Timeout: ${timeoutSeconds}s, MaxSize: $maxSize",
    );

    return TaskQueue<String>(
      maxConcurrentTasks: maxConcurrent,
      taskTimeout: const Duration(seconds: timeoutSeconds),
      maxQueueSize: maxSize,
    );
  }

  static TaskQueue<String> _initLargeQueue() {
    final maxConcurrent = flagService.internalUser ? 15 : 5;
    const timeoutSeconds = 60;
    const maxSize = 200;

    _logger.info(
      "Initializing Large Local Thumbnail Queue - "
      "MaxConcurrent: $maxConcurrent, Timeout: ${timeoutSeconds}s, MaxSize: $maxSize",
    );

    return TaskQueue<String>(
      maxConcurrentTasks: maxConcurrent,
      taskTimeout: const Duration(seconds: timeoutSeconds),
      maxQueueSize: maxSize,
    );
  }

  ///Assigned dimension will be the size of a grid item. The size will be
  ///assigned to the side which is smaller in dimension.
  void assignOptimizedImageDimensions() {
    if (widget.file.width == 0 || widget.file.height == 0) {
      return;
    }
    if (widget.file.width < widget.file.height) {
      optimizedImageWidth = widget.thumbnailSize;
    } else {
      optimizedImageHeight = widget.thumbnailSize;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.file.isRemoteOnlyFile) {
      _loadNetworkImage();
    } else {
      _loadLocalImage(context);
    }
    final galleryContext = GalleryContextState.of(context);
    Widget? image;
    if (_imageProvider != null) {
      image = Image(image: _imageProvider!, fit: widget.fit);
    }
    // todo: [2ndJuly22] pref-review if the content Widget which depends on
    // thumbnail fetch logic should be part of separate stateFull widget.
    // If yes, parent thumbnail widget can be stateless
    Widget? content;
    if (image != null) {
      if (widget.rawThumbnail) {
        return image;
      }
      final shouldShowOwnerAvatar =
          widget.shouldShowOwnerAvatar &&
          galleryContext?.galleryType != GalleryType.sharedPublicCollection;
      final List<Widget> contentChildren = [image];
      if (widget.shouldShowFavoriteIcon) {
        if (FavoritesService.instance.isFavoriteCache(
          widget.file,
          checkOnlyAlbum: widget.showFavForAlbumOnly,
        )) {
          contentChildren.add(const FavoriteOverlayIcon());
        }
      }

      if (widget.file.fileType != FileType.video &&
          widget.shouldShowLivePhotoOverlay &&
          widget.file.isLiveOrMotionPhoto) {
        contentChildren.add(const LivePhotoOverlayIcon());
      }
      if (shouldShowOwnerAvatar) {
        if (!widget.file.isOwner) {
          final owner = CollectionsService.instance.getFileOwner(
            widget.file.ownerID!,
            widget.file.collectionID,
          );
          contentChildren.add(
            OwnerAvatarOverlayIcon(owner, type: widget.ownerAvatarType),
          );
        } else if (widget.file.isCollect) {
          contentChildren.add(
            // Use -1 as userID for enforcing black avatar color
            OwnerAvatarOverlayIcon(
              User(id: -1, email: '', name: widget.file.uploaderName),
              type: widget.ownerAvatarType,
            ),
          );
        }
      }
      content = contentChildren.length == 1
          ? contentChildren.first
          : Stack(fit: StackFit.expand, children: contentChildren);
    }
    final List<Widget> viewChildren = [
      ThumbnailPlaceHolder(color: widget.placeholderColor),
      content ?? const SizedBox(),
    ];
    if (!widget.rawThumbnail && widget.file.fileType == FileType.video) {
      if (widget.shouldShowVideoDuration) {
        viewChildren.add(VideoOverlayDuration(duration: widget.file.duration));
      } else if (widget.shouldShowVideoOverlayIcon) {
        viewChildren.add(const VideoOverlayIcon());
      }
    }
    if (widget.shouldShowSyncStatus &&
        !widget.file.isUploaded &&
        !isLocalGalleryMode) {
      viewChildren.add(const UnSyncedIcon());
    }

    if (widget.file.isTrash) {
      viewChildren.add(TrashedFileOverlayText(widget.file as TrashFile));
    } else if (galleryContext?.type == GroupType.size) {
      viewChildren.add(FileSizeOverlayText(widget.file));
    } else if (widget.file.debugCaption != null) {
      viewChildren.add(FileOverlayText(widget.file.debugCaption!));
    }
    if (localSettings.showLocalIDOverThumbnails &&
        widget.file.localID != null) {
      viewChildren.add(
        Positioned(
          bottom: 4,
          left: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(0, 0, 0, 0.8),
              borderRadius: BorderRadius.circular(4),
            ),
            child: FittedBox(
              child: Text(
                "${widget.file.localID}",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: viewChildren,
    );
  }

  void _loadLocalImage(BuildContext context) {
    if (!_hasLoadedThumbnail &&
        !_errorLoadingLocalThumbnail &&
        !_isLoadingLocalThumbnail) {
      _isLoadingLocalThumbnail = true;
      final cachedSmallThumbnail = ThumbnailInMemoryLruCache.get(
        widget.file,
        _localCacheThumbnailSize,
      );
      if (cachedSmallThumbnail != null) {
        final imageProvider = Image.memory(
          cachedSmallThumbnail,
          cacheHeight: optimizedImageHeight,
          cacheWidth: optimizedImageWidth,
        ).image;
        _cacheAndRender(imageProvider);
        return;
      }
      if (widget.diskLoadDeferDuration != null) {
        Future.delayed(widget.diskLoadDeferDuration!, () {
          if (mounted) {
            _getThumbnailFromDisk();
          }
        });
      } else {
        _getThumbnailFromDisk();
      }
    }
  }

  Future _getThumbnailFromDisk() async {
    return _loadWithRetry()
        .then((thumbData) async {
          if (thumbData == null) {
            if (widget.file.isUploaded) {
              _logger.info("Removing localID reference for " + widget.file.tag);
              widget.file.localID = null;
              if (widget.file.isTrash) {
                unawaited(TrashDB.instance.update(widget.file as TrashFile));
              } else {
                unawaited(FilesDB.instance.update(widget.file));
              }
              _loadNetworkImage();
            } else {
              if (await doesLocalFileExist(widget.file) == false) {
                _logger.info("Deleting file " + widget.file.tag);
                await FilesDB.instance.deleteLocalFile(widget.file);
                Bus.instance.fire(
                  LocalPhotosUpdatedEvent(
                    [widget.file],
                    type: EventType.deletedFromDevice,
                    source: "thumbFileDeleted",
                  ),
                );
              }
            }
            return;
          }

          if (mounted) {
            final imageProvider = Image.memory(
              thumbData,
              cacheHeight: optimizedImageHeight,
              cacheWidth: optimizedImageWidth,
            ).image;
            _cacheAndRender(imageProvider);
          }
          ThumbnailInMemoryLruCache.put(
            widget.file,
            thumbData,
            _localCacheThumbnailSize,
          );
        })
        .catchError((e) {
          _errorLoadingLocalThumbnail = true;
          if (e is WidgetUnmountedException) {
            // Widget was unmounted - this is expected behavior
            _logger.fine(
              "Thumbnail loading cancelled: widget unmounted for localID: ${widget.file.localID}",
            );
          } else {
            _logger.warning(
              "Could not load thumbnail from disk for localID: ${widget.file.localID}",
              e,
            );
          }
        });
  }

  Future<Uint8List?> _loadWithRetry() async {
    int retryAttempts = 0;
    while (retryAttempts <= _maxLocalThumbnailRetries) {
      try {
        return await _getLocalThumbnailUsingHeapPriorityQueue();
      } catch (e) {
        // only retry for specific exceptions
        if (e is! TaskQueueTimeoutException &&
            e is! TaskQueueOverflowException &&
            e is! TaskQueueCancelledException) {
          rethrow;
        }
        //Do not retry if the widget is not mounted
        if (!mounted) {
          throw WidgetUnmountedException(
            "Thumbnail loading cancelled: widget unmounted",
          );
        }

        retryAttempts++;
        final backoff = Duration(
          milliseconds: 100 * pow(2, retryAttempts).toInt(),
        );
        if (retryAttempts <= _maxLocalThumbnailRetries) {
          _logger.warning(
            "Error getting local thumbnail for ${widget.file.displayName} (localID: ${widget.file.localID}) due to ${e.runtimeType}, retrying (attempt $retryAttempts) in ${backoff.inMilliseconds} ms",
            e,
          );
          await Future.delayed(backoff); // Exponential backoff
        } else {
          rethrow;
        }
      }
    }

    return null;
  }

  Future<Uint8List?> _getLocalThumbnailUsingHeapPriorityQueue() async {
    final localID = widget.file.localID;
    if (localID == null) {
      _logger.info(
        "Skipping local thumbnail load because localID is unavailable for ${widget.file.tag}",
      );
      return null;
    }

    final completer = Completer<Uint8List?>();

    late TaskQueue<String> relevantTaskQueue;
    if (widget.thumbnailSize == thumbnailLargeSize) {
      relevantTaskQueue = largeLocalThumbnailQueue;
      _localThumbnailQueueTaskId = [localID, "-large"].join();
    } else if (widget.thumbnailSize == thumbnailSmallSize) {
      relevantTaskQueue = smallLocalThumbnailQueue;
      _localThumbnailQueueTaskId = [localID, "-small"].join();
    } else {
      assert(false, "Invalid thumbnail size ${widget.thumbnailSize}");
      _logger.severe(
        "Invalid thumbnail size ${widget.thumbnailSize} for file ${widget.file.displayName}",
      );
    }

    await relevantTaskQueue.addTask(_localThumbnailQueueTaskId!, () async {
      late final Uint8List? thumbnailBytes;
      try {
        thumbnailBytes = await getThumbnailFromLocal(
          widget.file,
          size: widget.thumbnailSize,
        );
        completer.complete(thumbnailBytes);
      } catch (e) {
        completer.completeError(e);
      }
    });

    return completer.future;
  }

  void _loadNetworkImage() {
    if (!_hasLoadedThumbnail &&
        !_errorLoadingRemoteThumbnail &&
        !_isLoadingRemoteThumbnail) {
      _isLoadingRemoteThumbnail = true;
      final cachedThumbnail = ThumbnailInMemoryLruCache.get(widget.file);
      if (cachedThumbnail != null) {
        final imageProvider = Image.memory(
          cachedThumbnail,
          cacheHeight: optimizedImageHeight,
          cacheWidth: optimizedImageWidth,
        ).image;
        _cacheAndRender(imageProvider);
        return;
      }

      if (widget.serverLoadDeferDuration != null) {
        Future.delayed(widget.serverLoadDeferDuration!, () {
          if (mounted) {
            _getThumbnailFromServer();
          }
        });
      } else {
        _getThumbnailFromServer();
      }
    }
  }

  void _getThumbnailFromServer() async {
    try {
      final thumbnail = await getThumbnailFromServer(widget.file);
      if (mounted) {
        final imageProvider = Image.memory(
          thumbnail,
          cacheHeight: optimizedImageHeight,
          cacheWidth: optimizedImageWidth,
        ).image;
        _cacheAndRender(imageProvider);
      }
    } catch (e) {
      if (e is RequestCancelledError) {
        if (mounted) {
          _logger.info(
            "Thumbnail request was aborted although it is in view, will retry",
          );
          _reset();
          setState(() {});
        }
      } else {
        _logger.severe("Could not load image " + widget.file.toString(), e);
        _errorLoadingRemoteThumbnail = true;
      }
    }
  }

  void _cacheAndRender(ImageProvider<Object> imageProvider) {
    if (mounted) {
      setState(() {
        _imageProvider = imageProvider;
        _hasLoadedThumbnail = true;
      });
      precacheImage(imageProvider, context);
    }
  }

  void _reset() {
    _hasLoadedThumbnail = false;
    _isLoadingLocalThumbnail = false;
    _isLoadingRemoteThumbnail = false;
    _errorLoadingLocalThumbnail = false;
    _errorLoadingRemoteThumbnail = false;
    _imageProvider = null;
  }
}

import 'dart:async';
import 'dart:convert';
import "dart:io";
import "dart:math" as math;

import "package:chewie/chewie.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:logging/logging.dart";
import "package:media_extension/media_extension.dart";
import "package:media_extension/media_extension_action_types.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photo_manager_image_provider/photo_manager_image_provider.dart";
import "package:photo_view/photo_view.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/gallery_type.dart";
import "package:photos/models/metadata/file_magic.dart";
import "package:photos/module/metadata/local_file.dart";
import "package:photos/module/metadata/video.dart";
import "package:photos/services/app_lifecycle_service.dart";
import "package:photos/ui/viewer/file/detail_page.dart";
import "package:receive_sharing_intent/receive_sharing_intent.dart";
import "package:video_player/video_player.dart";

class FileViewer extends StatefulWidget {
  final SharedMediaFile? sharedMediaFile;
  const FileViewer({super.key, this.sharedMediaFile});

  @override
  State<StatefulWidget> createState() {
    return FileViewerState();
  }
}

class FileViewerState extends State<FileViewer> {
  static const int _reviewGalleryWindowSize = 80;
  static const int _reviewGallerySearchPageSize = 200;

  final action = AppLifecycleService.instance.mediaExtensionAction;
  ChewieController? controller;
  VideoPlayerController? videoController;
  final Logger _logger = Logger("FileViewer");
  double? aspectRatio;
  Future<AssetEntity?>? mediaStoreAssetFuture;
  Future<DetailPageConfiguration?>? reviewGalleryConfigFuture;
  Future<Uint8List?>? grantedImageBytesFuture;
  bool _isInitializingVideoController = false;
  bool _isClosingViewer = false;
  bool get _isExternalView =>
      widget.sharedMediaFile == null &&
      action.action == IntentAction.view &&
      (action.type == MediaType.image || action.type == MediaType.video);

  Widget _boundedPhotoView(ImageProvider imageProvider) {
    return PhotoView(
      imageProvider: imageProvider,
      filterQuality: FilterQuality.high,
      initialScale: PhotoViewComputedScale.contained,
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 3.0,
      strictScale: true,
    );
  }

  @override
  void initState() {
    _logger.info("Initializing FileViewer");
    super.initState();
    if (_isExternalView) {
      mediaStoreAssetFuture = _loadMediaStoreAsset(action.data);
      reviewGalleryConfigFuture = _loadReviewGalleryConfig();
    }
    if (action.type == MediaType.video ||
        widget.sharedMediaFile?.type == SharedMediaType.video) {
      if (!_isExternalView) {
        _initializeVideoController();
      }
    } else if (action.type == MediaType.image &&
        mediaStoreAssetFuture == null) {
      mediaStoreAssetFuture = _loadMediaStoreAsset(action.data);
    }
  }

  Future<void> _initializeVideoController() async {
    if (_isInitializingVideoController || controller != null) {
      return;
    }
    _isInitializingVideoController = true;
    try {
      await _fetchAspectRatio();
      if (!mounted) {
        return;
      }
      initController();
    } finally {
      _isInitializingVideoController = false;
    }
  }

  Future<void> _fetchAspectRatio() async {
    try {
      final videoPath = widget.sharedMediaFile?.path ?? action.data;
      if (videoPath == null) {
        _logger.warning("Video path is null, using default aspect ratio");
        aspectRatio = 16 / 9;
        return;
      }

      final videoFile = File(videoPath);
      if (!await videoFile.exists()) {
        _logger.warning(
          "Video file does not exist, using default aspect ratio",
        );
        aspectRatio = 16 / 9;
        return;
      }

      final videoProps = await getVideoProps(videoFile);
      if (videoProps != null &&
          videoProps.width != null &&
          videoProps.height != null &&
          videoProps.height != 0) {
        aspectRatio = videoProps.width! / videoProps.height!;
        _logger.info("Fetched video aspect ratio: $aspectRatio");
      } else {
        _logger.warning(
          "Could not get video dimensions, using default aspect ratio",
        );
        aspectRatio = 16 / 9;
      }
    } catch (e) {
      _logger.severe("Error fetching video aspect ratio: $e");
      aspectRatio = 16 / 9;
    }
  }

  @override
  void dispose() {
    videoController?.dispose();
    controller?.dispose();
    super.dispose();
  }

  void initController() async {
    videoController = VideoPlayerController.contentUri(
      widget.sharedMediaFile?.path != null
          ? Uri.parse(widget.sharedMediaFile!.path)
          : Uri.parse(action.data!),
    );
    controller = ChewieController(
      videoPlayerController: videoController!,
      autoInitialize: true,
      aspectRatio: aspectRatio ?? 16 / 9,
      autoPlay: true,
      looping: true,
      showOptions: false,
      materialProgressColors: ChewieProgressColors(
        playedColor: const Color.fromRGBO(45, 194, 98, 1.0),
        handleColor: Colors.white,
        bufferedColor: Colors.white,
      ),
    );
    controller!.addListener(() {
      if (!controller!.isFullScreen) {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      }
    });
    if (mounted) {
      setState(() {});
    }
  }

  Future<AssetEntity?>? _loadMediaStoreAsset(String? data) {
    final uri = data == null ? null : Uri.tryParse(data);
    final id = uri == null ? null : _mediaStoreAssetId(uri);
    if (id == null) {
      return null;
    }
    return AssetEntity.fromId(id);
  }

  String? _mediaStoreAssetId(Uri uri) {
    if (uri.scheme != "content") {
      return null;
    }
    if (uri.authority == "media") {
      final mediaSegmentIndex = uri.pathSegments.lastIndexOf("media");
      if (mediaSegmentIndex >= 0 &&
          mediaSegmentIndex < uri.pathSegments.length - 1) {
        return uri.pathSegments[mediaSegmentIndex + 1];
      }
      if (uri.pathSegments.isNotEmpty) {
        final id = uri.pathSegments.last;
        if (int.tryParse(id) != null) {
          return id;
        }
      }
    }
    if (uri.authority == "com.android.providers.media.documents" &&
        uri.pathSegments.isNotEmpty) {
      final documentId = uri.pathSegments.last;
      final id = documentId.split(":").last;
      if (id.isNotEmpty) {
        return id;
      }
    }
    return null;
  }

  Future<DetailPageConfiguration?> _loadReviewGalleryConfig() async {
    final assetFuture = mediaStoreAssetFuture;
    if (assetFuture == null) {
      return null;
    }
    final targetAsset = await assetFuture;
    if (targetAsset == null) {
      return null;
    }

    try {
      final source = await _findReviewGallerySource(targetAsset);
      if (source == null) {
        _logger.info("Could not find containing gallery for ${targetAsset.id}");
        return null;
      }
      final assets = await _reviewGalleryWindow(source);
      var selectedIndex = assets.indexWhere(
        (asset) => asset.id == targetAsset.id,
      );
      if (selectedIndex < 0) {
        assets.insert(0, targetAsset);
        selectedIndex = 0;
      }
      final files = <EnteFile>[];
      var fileSelectedIndex = selectedIndex;
      for (var index = 0; index < assets.length; index++) {
        try {
          if (index == selectedIndex) {
            fileSelectedIndex = files.length;
          }
          files.add(await _fileFromAsset(source.path.name, assets[index]));
        } catch (e, s) {
          if (index == selectedIndex) {
            rethrow;
          }
          _logger.warning("Skipping adjacent review asset", e, s);
        }
      }
      if (files.isEmpty) {
        return null;
      }
      return DetailPageConfiguration(
        files,
        fileSelectedIndex,
        "external_review_gallery",
        isLocalOnlyContext: true,
        galleryType: GalleryType.localFolder,
        onBackPressed: (_) => _closeViewer(),
      );
    } catch (e, s) {
      _logger.warning("Failed to load review gallery", e, s);
      return null;
    }
  }

  Future<_ReviewGallerySource?> _findReviewGallerySource(
    AssetEntity targetAsset,
  ) async {
    final source = await _findReviewGallerySourceInPaths(
      targetAsset,
      paths: await _reviewGalleryPaths(hasAll: false),
    );
    if (source != null) {
      return source;
    }
    return _findReviewGallerySourceInPaths(
      targetAsset,
      paths: await _reviewGalleryPaths(hasAll: true),
    );
  }

  Future<List<AssetPathEntity>> _reviewGalleryPaths({required bool hasAll}) {
    return PhotoManager.getAssetPathList(
      hasAll: hasAll,
      type: RequestType.common,
      filterOption: _reviewGalleryFilterOption(),
    );
  }

  Future<_ReviewGallerySource?> _findReviewGallerySourceInPaths(
    AssetEntity targetAsset, {
    required List<AssetPathEntity> paths,
  }) async {
    final preferredName = _preferredPathName(targetAsset);
    paths.sort((a, b) {
      final aMatches = a.name == preferredName;
      final bMatches = b.name == preferredName;
      if (aMatches == bMatches) {
        return 0;
      }
      return aMatches ? -1 : 1;
    });

    for (final path in paths) {
      final count = await path.assetCountAsync;
      final index = await _indexOfAsset(path, targetAsset.id, count);
      if (index != null) {
        return _ReviewGallerySource(
          path: path,
          targetIndex: index,
          count: count,
        );
      }
    }
    return null;
  }

  FilterOptionGroup _reviewGalleryFilterOption() {
    final filterOptionGroup = FilterOptionGroup();
    const assetOption = FilterOption(
      needTitle: true,
      sizeConstraint: SizeConstraint(ignoreSize: true),
    );
    filterOptionGroup.setOption(AssetType.image, assetOption);
    filterOptionGroup.setOption(AssetType.video, assetOption);
    filterOptionGroup.createTimeCond = DateTimeCond.def().copyWith(
      ignore: true,
    );
    filterOptionGroup.addOrderOption(
      const OrderOption(type: OrderOptionType.createDate, asc: false),
    );
    return filterOptionGroup;
  }

  String? _preferredPathName(AssetEntity asset) {
    final relativePath = asset.relativePath;
    if (relativePath == null || relativePath.isEmpty) {
      return null;
    }
    final segments = relativePath
        .split("/")
        .where((segment) => segment.trim().isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) {
      return null;
    }
    return segments.last;
  }

  Future<int?> _indexOfAsset(
    AssetPathEntity path,
    String assetId,
    int count,
  ) async {
    for (var start = 0; start < count; start += _reviewGallerySearchPageSize) {
      final end = math.min(count, start + _reviewGallerySearchPageSize);
      final assets = await path.getAssetListRange(start: start, end: end);
      final index = assets.indexWhere((asset) => asset.id == assetId);
      if (index >= 0) {
        return start + index;
      }
    }
    return null;
  }

  Future<List<AssetEntity>> _reviewGalleryWindow(
    _ReviewGallerySource source,
  ) async {
    const halfWindow = _reviewGalleryWindowSize ~/ 2;
    final initialEnd = math.min(
      source.count,
      source.targetIndex + halfWindow + 1,
    );
    final start = math.max(
      0,
      math.min(
        source.targetIndex - halfWindow,
        initialEnd - _reviewGalleryWindowSize,
      ),
    );
    final end = math.min(source.count, start + _reviewGalleryWindowSize);
    return source.path.getAssetListRange(start: start, end: end);
  }

  Future<EnteFile> _fileFromAsset(String pathName, AssetEntity asset) async {
    final file = fileFromAsset(pathName, asset);
    file.pubMagicMetadata = PubMagicMetadata(
      w: asset.orientatedWidth,
      h: asset.orientatedHeight,
    );
    return file;
  }

  Future<Uint8List?> _readGrantedImageBytes(String uri) async {
    try {
      final bytes = await MediaExtension().readUriBytes(uri);
      if (bytes == null || bytes.isEmpty) {
        _logger.severe("failed to read image bytes for $uri");
        return null;
      }
      return bytes;
    } catch (e, s) {
      _logger.severe("failed to read image bytes for $uri", e, s);
      return null;
    }
  }

  Widget _buildGrantedImageFallback(String data) {
    final uri = Uri.tryParse(data);
    if (uri?.scheme != "content") {
      _logger.severe("unsupported image uri $data");
      return const Icon(Icons.error);
    }
    final future = grantedImageBytesFuture ??= _readGrantedImageBytes(data);
    return FutureBuilder<Uint8List?>(
      future: future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null) {
          return _boundedPhotoView(MemoryImage(bytes));
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const CircularProgressIndicator();
        }
        return const Icon(Icons.error);
      },
    );
  }

  Widget _buildImageViewer() {
    final sharedMediaPath = widget.sharedMediaFile?.path;
    if (sharedMediaPath != null) {
      return _boundedPhotoView(Image.file(File(sharedMediaPath)).image);
    }

    final data = action.data;
    if (data == null) {
      _logger.severe("image data is null");
      return const Icon(Icons.error);
    }

    final uri = Uri.tryParse(data);
    if (uri?.scheme == "file") {
      return _boundedPhotoView(FileImage(File(uri!.toFilePath())));
    }

    final assetFuture = mediaStoreAssetFuture;
    if (assetFuture != null) {
      return FutureBuilder<AssetEntity?>(
        future: assetFuture,
        builder: (context, snapshot) {
          final asset = snapshot.data;
          if (asset == null) {
            if (snapshot.connectionState == ConnectionState.done) {
              _logger.warning(
                "failed to resolve media store image, falling back to uri",
              );
              return _buildGrantedImageFallback(data);
            }
            return const CircularProgressIndicator();
          }
          return _boundedPhotoView(AssetEntityImageProvider(asset));
        },
      );
    }

    if (uri?.scheme == "content") {
      return _buildGrantedImageFallback(data);
    }

    if (uri != null && uri.scheme.isNotEmpty) {
      _logger.severe("unsupported image uri $data");
      return const Icon(Icons.error);
    }

    try {
      return _boundedPhotoView(MemoryImage(base64Decode(data)));
    } catch (e, s) {
      _logger.severe("failed to decode shared image payload", e, s);
      return const Icon(Icons.error);
    }
  }

  Widget _buildVideoViewer() {
    if (controller != null) {
      return Chewie(controller: controller!);
    }
    unawaited(_initializeVideoController());
    return const CircularProgressIndicator();
  }

  Widget _buildSingleFileScaffold() {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _closeViewer,
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: (() {
                if (action.type == MediaType.image ||
                    widget.sharedMediaFile?.type == SharedMediaType.image) {
                  return _buildImageViewer();
                } else if (action.type == MediaType.video ||
                    widget.sharedMediaFile?.type == SharedMediaType.video) {
                  return _buildVideoViewer();
                } else {
                  _logger.severe(
                    'unsupported file type ${action.type} or ${widget.sharedMediaFile?.type}',
                  );
                  return const Icon(Icons.error);
                }
              })(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewGalleryOrFallback() {
    final configFuture = reviewGalleryConfigFuture;
    if (configFuture == null) {
      return _buildSingleFileScaffold();
    }
    return FutureBuilder<DetailPageConfiguration?>(
      future: configFuture,
      builder: (context, snapshot) {
        final config = snapshot.data;
        if (config != null) {
          return DetailPage(config);
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return _buildSingleFileScaffold();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _logger.info("Building FileViewer");
    final scaffold = _isExternalView
        ? _buildReviewGalleryOrFallback()
        : _buildSingleFileScaffold();
    if (!_isExternalView) {
      return scaffold;
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        unawaited(_closeViewer());
      },
      child: scaffold,
    );
  }

  Future<void> _closeViewer() async {
    if (_isClosingViewer) {
      return;
    }
    _isClosingViewer = true;
    try {
      await SystemChannels.platform.invokeMethod('SystemNavigator.pop');
    } finally {
      _isClosingViewer = false;
    }
  }
}

class _ReviewGallerySource {
  final AssetPathEntity path;
  final int targetIndex;
  final int count;

  const _ReviewGallerySource({
    required this.path,
    required this.targetIndex,
    required this.count,
  });
}

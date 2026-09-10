import "dart:async";
import "dart:developer";
import "dart:io";

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/divider_widget.dart";
import "package:exif_reader/exif_reader.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/core/user_config.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/models/ffmpeg/ffprobe_props.dart";
import "package:photos/models/file/extensions/file_props.dart";
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import "package:photos/models/location/location.dart";
import "package:photos/models/metadata/file_magic.dart";
import "package:photos/module/download/file.dart";
import "package:photos/module/metadata/exif.dart";
import "package:photos/module/metadata/video.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/file_magic_service.dart";
import 'package:photos/ui/viewer/file/file_caption_widget.dart';
import "package:photos/ui/viewer/file_details/added_by_widget.dart";
import "package:photos/ui/viewer/file_details/albums_item_widget.dart";
import "package:photos/ui/viewer/file_details/creation_time_item_widget.dart";
import 'package:photos/ui/viewer/file_details/exif_item_widgets.dart';
import "package:photos/ui/viewer/file_details/file_info_faces_item_widget.dart";
import "package:photos/ui/viewer/file_details/file_info_pets_item_widget.dart";
import "package:photos/ui/viewer/file_details/file_properties_item_widget.dart";
import "package:photos/ui/viewer/file_details/location_tags_widget.dart";
import "package:photos/ui/viewer/file_details/preview_properties_item_widget.dart";
import "package:photos/ui/viewer/file_details/video_exif_item.dart";

class FileDetailsWidget extends StatefulWidget {
  final EnteFile file;
  final ScrollController? scrollController;

  const FileDetailsWidget(this.file, {this.scrollController, super.key});

  @override
  State<FileDetailsWidget> createState() => _FileDetailsWidgetState();
}

class _FileDetailsWidgetState extends State<FileDetailsWidget> {
  final Map<String, dynamic> _exifData = {
    "focalLength": null,
    "fNumber": null,
    "resolution": null,
    "takenOnDevice": null,
    "exposureTime": null,
    "ISO": null,
    "megaPixels": null,
    "lat": null,
    "long": null,
    "latRef": null,
    "longRef": null,
  };

  late final StreamSubscription<PeopleChangedEvent> _peopleChangedEvent;

  bool _isImage = false;
  late int _currentUserID;
  bool showExifListTile = false;
  final ValueNotifier<Map<String, IfdTag>?> _exifNotifier = ValueNotifier(null);
  final ValueNotifier<bool> hasLocationData = ValueNotifier(false);
  final Logger _logger = Logger("_FileDetailsWidgetState");
  final ValueNotifier<FFProbeProps?> _videoMetadataNotifier = ValueNotifier(
    null,
  );

  @override
  void initState() {
    debugPrint('file_details_sheet initState');
    _currentUserID = Configuration.instance.getUserIDV2();
    hasLocationData.value = widget.file.hasLocation;
    _isImage =
        widget.file.fileType == FileType.image ||
        widget.file.fileType == FileType.livePhoto;

    _peopleChangedEvent = Bus.instance.on<PeopleChangedEvent>().listen((event) {
      setState(() {});
    });

    _exifNotifier.addListener(() {
      if (_exifNotifier.value != null && !widget.file.hasLocation) {
        _updateLocationFromExif(
          locationFromExif(_exifNotifier.value!),
        ).ignore();
      }
    });
    _videoMetadataNotifier.addListener(() {
      if (_videoMetadataNotifier.value?.location != null &&
          !widget.file.hasLocation) {
        _updateLocationFromExif(
          _videoMetadataNotifier.value?.location,
        ).ignore();
      }
    });

    if (!widget.file.isDeviceTrash) {
      if (_isImage) {
        _exifNotifier.addListener(() {
          if (_exifNotifier.value != null) {
            _generateExifForDetails(_exifNotifier.value!);
          }
          showExifListTile =
              _exifData["focalLength"] != null ||
              _exifData["fNumber"] != null ||
              _exifData["takenOnDevice"] != null ||
              _exifData["exposureTime"] != null ||
              _exifData["ISO"] != null;
        });
      } else if (flagService.internalUser && widget.file.isVideo) {
        getMediaInfo();
      }
      getExif(widget.file).then<void>(
        (exif) {
          if (mounted) {
            _exifNotifier.value = exif;
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          _logger.warning(
            "Failed to load file details EXIF",
            error,
            stackTrace,
          );
        },
      );
    }

    super.initState();
  }

  Future<void> getMediaInfo() async {
    final File? originFile = await getFile(widget.file, isOrigin: true);
    if (originFile == null) return;
    final properties = await getVideoProps(originFile);
    if (!mounted) return;
    _videoMetadataNotifier.value = properties;
    if (kDebugMode) {
      log("videoCustomProps ${properties.toString()}");
      log("PropData ${properties?.propData.toString()}");
    }
    setState(() {});
  }

  @override
  void dispose() {
    _exifNotifier.dispose();
    hasLocationData.dispose();
    _videoMetadataNotifier.dispose();
    _peopleChangedEvent.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final bool isFileOwner =
        file.ownerID == null || file.ownerID == _currentUserID;

    final fileDetailsTiles = <Widget>[];
    final bool canEditCaption = isFileOwner && !file.isTrash;
    fileDetailsTiles.add(
      !widget.file.isUploaded ||
              (!canEditCaption && (widget.file.caption?.isEmpty ?? true))
          ? const SizedBox(height: 16)
          : Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              child: canEditCaption
                  ? FileCaptionWidget(file: widget.file)
                  : FileCaptionReadyOnly(caption: widget.file.caption!),
            ),
    );
    final hasPreview =
        widget.file.uploadedFileID != null &&
        fileDataService.previewIds.containsKey(widget.file.uploadedFileID);
    fileDetailsTiles.addAll([
      MenuGroupComponent(
        items: [
          CreationTimeItem(file, _currentUserID),
          ValueListenableBuilder(
            valueListenable: _exifNotifier,
            builder: (context, _, _) => FilePropertiesItemWidget(
              file,
              _isImage,
              _exifData,
              _currentUserID,
            ),
          ),
          ValueListenableBuilder(
            valueListenable: _exifNotifier,
            builder: (context, _, _) => showExifListTile
                ? BasicExifItemWidget(_exifData)
                : const SizedBox.shrink(),
          ),
        ],
      ),
      const SizedBox(height: Spacing.xxl),
    ]);

    if (hasGrantedMLConsent) {
      fileDetailsTiles.addAll([
        FacesItemWidget(file),
        const SizedBox(height: Spacing.xxl),
      ]);
      if (flagService.petEnabled && localSettings.petRecognitionEnabled) {
        fileDetailsTiles.addAll([
          PetsItemWidget(file),
          const FileDetailsDivider(),
        ]);
      }
    }

    fileDetailsTiles.addAll([
      ValueListenableBuilder(
        valueListenable: hasLocationData,
        builder: (context, bool value, _) {
          return value
              ? Column(
                  children: [
                    LocationTagsWidget(widget.file),
                    const SizedBox(height: Spacing.xxl),
                  ],
                )
              : const SizedBox.shrink();
        },
      ),
    ]);

    if (!file.isTrash) {
      fileDetailsTiles.addAll([
        AlbumsItemWidget(file, _currentUserID),
        const SizedBox(height: Spacing.xxl),
      ]);
    }

    if (_isImage && !file.isDeviceTrash) {
      fileDetailsTiles.addAll([
        MenuGroupComponent(
          items: [
            if (hasPreview)
              PreviewPropertiesItemWidget(
                file,
                _isImage,
                _exifData,
                _currentUserID,
              ),
            ValueListenableBuilder(
              valueListenable: _exifNotifier,
              builder: (context, _, _) =>
                  AllExifItemWidget(file, _exifNotifier.value),
            ),
          ],
        ),
        const SizedBox(height: Spacing.xxl),
      ]);
    } else if (file.isVideo) {
      final items = <Widget>[
        if (hasPreview)
          PreviewPropertiesItemWidget(
            file,
            _isImage,
            _exifData,
            _currentUserID,
          ),
        if (flagService.internalUser && !file.isDeviceTrash)
          ValueListenableBuilder(
            valueListenable: _videoMetadataNotifier,
            builder: (context, value, _) => VideoExifRowItem(file, value),
          ),
      ];
      if (items.isNotEmpty) {
        fileDetailsTiles.addAll([
          MenuGroupComponent(items: items),
          const SizedBox(height: Spacing.xxl),
        ]);
      }
    }

    return SafeArea(
      top: false,
      child: Scrollbar(
        thickness: 4,
        radius: const Radius.circular(2),
        thumbVisibility: true,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: CustomScrollView(
            controller: widget.scrollController,
            physics: const ClampingScrollPhysics(),
            shrinkWrap: true,
            slivers: <Widget>[
              SliverAppBar(
                automaticallyImplyLeading: false,
                backgroundColor: context.componentColors.backgroundBase,
                surfaceTintColor: Colors.transparent,
                primary: false,
                pinned: true,
                centerTitle: false,
                toolbarHeight: 38,
                titleSpacing: 0,
                title: Text(
                  context.strings.details,
                  style: TextStyles.h2.copyWith(
                    color: context.componentColors.textBase,
                  ),
                ),
                actions: [
                  IconButtonComponent(
                    tooltip: context.strings.close,
                    variant: IconButtonComponentVariant.circular,
                    shouldSurfaceExecutionStates: false,
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedCancel01,
                      size: IconSizes.small,
                    ),
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SliverToBoxAdapter(child: SizedBox(height: Spacing.lg)),
              SliverToBoxAdapter(child: AddedByWidget(widget.file)),
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  return fileDetailsTiles[index];
                }, childCount: fileDetailsTiles.length),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Some devices leave file location empty even when EXIF contains it.
  Future<void> _updateLocationFromExif(Location? locationDataFromExif) async {
    if (!widget.file.isUploaded || widget.file.ownerID == null) {
      return;
    }
    if (widget.file.ownerID != _currentUserID) {
      return;
    }
    try {
      if (locationDataFromExif?.latitude != null &&
          locationDataFromExif?.longitude != null) {
        widget.file.location = locationDataFromExif;
        await FileMagicService.instance.updatePublicMagicMetadata(
          [widget.file],
          {
            latKey: locationDataFromExif!.latitude,
            longKey: locationDataFromExif.longitude,
          },
        );
        hasLocationData.value = true;
      }
    } catch (e, s) {
      _logger.severe("Error while updating location from EXIF", e, s);
    }
  }

  void _generateExifForDetails(Map<String, IfdTag> exif) {
    if (exif["EXIF FocalLength"] != null) {
      _exifData["focalLength"] = _formatExifRatio(
        exif["EXIF FocalLength"]!.values.toList()[0] as Ratio,
      );
    }

    if (exif["EXIF FNumber"] != null) {
      _exifData["fNumber"] = _formatExifRatio(
        exif["EXIF FNumber"]!.values.toList()[0] as Ratio,
      );
    }
    final imageWidth = _firstPositiveDimensionTag(exif, const [
      "EXIF ExifImageWidth",
      "Image ImageWidth",
    ]);
    final imageLength = _firstPositiveDimensionTag(exif, const [
      "EXIF ExifImageLength",
      "Image ImageLength",
    ]);
    if (imageWidth != null && imageLength != null) {
      _exifData["resolution"] = '$imageWidth x $imageLength';
      final double megaPixels =
          (imageWidth.values.firstAsInt() * imageLength.values.firstAsInt()) /
          1000000;
      final double roundedMegaPixels = (megaPixels * 10).round() / 10.0;
      _exifData['megaPixels'] = roundedMegaPixels..toStringAsFixed(1);
    } else {
      debugPrint("No image width/height");
    }
    if (exif["Image Make"] != null && exif["Image Model"] != null) {
      _exifData["takenOnDevice"] =
          exif["Image Make"].toString() + " " + exif["Image Model"].toString();
    }

    if (exif["EXIF ExposureTime"] != null) {
      _exifData["exposureTime"] = _formatExposureTime(
        exif["EXIF ExposureTime"]!,
      );
    }
    if (exif["EXIF ISOSpeedRatings"] != null) {
      _exifData['ISO'] = exif["EXIF ISOSpeedRatings"].toString();
    }
  }

  String _formatExifRatio(Ratio ratio) {
    if (ratio.denominator == 0) {
      return ratio.toString();
    }
    final value = ratio.numerator / ratio.denominator;
    return value.toStringAsFixed(2).replaceFirst(RegExp(r"\.?0+$"), "");
  }

  String _formatExposureTime(IfdTag exposureTimeTag) {
    final values = exposureTimeTag.values.toList();
    if (values.isEmpty) {
      return exposureTimeTag.toString();
    }

    final value = values[0];
    if (value is! Ratio) {
      return exposureTimeTag.toString();
    }

    final numerator = value.numerator;
    final denominator = value.denominator;

    if (denominator == 0) {
      return exposureTimeTag.toString();
    }

    final double seconds = numerator / denominator;

    if (seconds >= 1) {
      if (seconds == seconds.roundToDouble()) {
        return "${seconds.toInt()}s";
      }
      return "${seconds.toStringAsFixed(1)}s";
    } else {
      final reciprocal = (1 / seconds).round();
      return "1/$reciprocal";
    }
  }

  IfdTag? _firstPositiveDimensionTag(
    Map<String, IfdTag> exif,
    List<String> keys,
  ) {
    for (final key in keys) {
      final tag = exif[key];
      if (tag != null && tag.values.firstAsInt() > 0) {
        return tag;
      }
    }
    return null;
  }
}

class FileDetailsDivider extends StatelessWidget {
  const FileDetailsDivider({super.key});

  @override
  Widget build(BuildContext context) {
    const dividerPadding = EdgeInsets.symmetric(vertical: 9.5);
    return const DividerWidget(
      dividerType: DividerType.menu,
      divColorHasBlur: false,
      padding: dividerPadding,
    );
  }
}

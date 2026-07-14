import "dart:async";
import "dart:developer";
import "dart:io";

import "package:ente_components/ente_components.dart";
import "package:exif_reader/exif_reader.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/core/user_config.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/generated/l10n.dart";
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

  const FileDetailsWidget(this.file, {super.key});

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
    getExif(widget.file).then((exif) {
      _exifNotifier.value = exif;
    });

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
    final l10n = AppLocalizations.of(context);
    final bool isFileOwner =
        file.ownerID == null || file.ownerID == _currentUserID;
    final bool canEditCaption = isFileOwner && !file.isTrash;
    final bool showCaption =
        file.isUploaded &&
        !(!canEditCaption && (file.caption?.isEmpty ?? true));
    final bool hasPreview =
        file.uploadedFileID != null &&
        fileDataService.previewIds.containsKey(file.uploadedFileID);

    final sections = <Widget>[];

    sections.add(
      _sectionPadding(
        ValueListenableBuilder(
          valueListenable: _exifNotifier,
          builder: (context, _, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AddedByWidget(file),
              if (showCaption)
                Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.lg),
                  child: canEditCaption
                      ? FileCaptionWidget(file: file)
                      : FileCaptionReadyOnly(caption: file.caption!),
                ),
              MenuGroupComponent(
                items: [
                  FilePropertiesItemWidget(
                    file,
                    _isImage,
                    _exifData,
                    _currentUserID,
                  ),
                  CreationTimeItem(file, _currentUserID),
                  if (showExifListTile) BasicExifItemWidget(_exifData),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (hasGrantedMLConsent) {
      sections.add(_sectionPadding(FacesItemWidget(file)));
      if (flagService.petEnabled && localSettings.petRecognitionEnabled) {
        sections.add(PetsItemWidget(file));
      }
    }

    sections.add(
      ValueListenableBuilder<bool>(
        valueListenable: hasLocationData,
        builder: (context, hasLocation, _) => hasLocation
            ? _sectionPadding(LocationTagsWidget(file))
            : const SizedBox.shrink(),
      ),
    );

    if (!file.isTrash) {
      sections.add(_sectionPadding(AlbumsItemWidget(file, _currentUserID)));
    }

    if (_isImage) {
      sections.add(
        ValueListenableBuilder(
          valueListenable: _exifNotifier,
          builder: (context, _, _) => MenuGroupComponent(
            items: [
              if (hasPreview)
                PreviewPropertiesItemWidget(
                  file,
                  _isImage,
                  _exifData,
                  _currentUserID,
                ),
              AllExifItemWidget(file, _exifNotifier.value),
            ],
          ),
        ),
      );
    } else if (file.isVideo) {
      sections.add(
        ValueListenableBuilder(
          valueListenable: _videoMetadataNotifier,
          builder: (context, value, _) {
            final items = <Widget>[
              if (hasPreview)
                PreviewPropertiesItemWidget(
                  file,
                  _isImage,
                  _exifData,
                  _currentUserID,
                ),
              if (flagService.internalUser) VideoExifRowItem(file, value),
            ];
            if (items.isEmpty) {
              return const SizedBox.shrink();
            }
            return MenuGroupComponent(items: items);
          },
        ),
      );
    }

    return BottomSheetComponent(
      title: l10n.details,
      isKeyboardAware: true,
      isScrollable: true,
      snap: true,
      initialChildSize: 0.75,
      snapSizes: const [0.5, 0.75, 0.95],
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: sections,
      ),
    );
  }

  Widget _sectionPadding(Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: Spacing.xxl),
    child: child,
  );

  //This code is for updating the location of files in which location data is
  //missing and the EXIF has location data. This is only happens for a
  //certain specific minority of devices.
  Future<void> _updateLocationFromExif(Location? locationDataFromExif) async {
    // If the file is not uploaded or the file is not owned by the current user
    // then we don't need to update the location.
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
      _exifData["focalLength"] =
          (exif["EXIF FocalLength"]!.values.toList()[0] as Ratio).numerator /
          (exif["EXIF FocalLength"]!.values.toList()[0] as Ratio).denominator;
    }

    if (exif["EXIF FNumber"] != null) {
      _exifData["fNumber"] =
          (exif["EXIF FNumber"]!.values.toList()[0] as Ratio).numerator /
          (exif["EXIF FNumber"]!.values.toList()[0] as Ratio).denominator;
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

  /// Formats exposure time from EXIF data into a human-readable string.
  ///
  /// For shutter speeds >= 1 second, displays as decimal with 's' suffix (e.g., "1.3s")
  /// For shutter speeds < 1 second, displays as a fraction (e.g., "1/100")
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
      // For exposures >= 1 second, show as decimal seconds
      if (seconds == seconds.roundToDouble()) {
        return "${seconds.toInt()}s";
      }
      return "${seconds.toStringAsFixed(1)}s";
    } else {
      // For exposures < 1 second, always convert to 1/x format
      // e.g., 529/200000 → 1/378
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

import "dart:async";
import "dart:developer";
import "dart:io";

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
import "package:photos/service_locator.dart";
import "package:photos/services/file_magic_service.dart";
import 'package:photos/theme/ente_theme.dart';
import 'package:photos/ui/components/buttons/icon_button_widget.dart';
import "package:photos/ui/components/divider_widget.dart";
import 'package:photos/ui/components/title_bar_widget.dart';
import 'package:photos/ui/viewer/file/file_caption_widget.dart';
import "package:photos/ui/viewer/file_details/added_by_widget.dart";
import "package:photos/ui/viewer/file_details/albums_item_widget.dart";
import 'package:photos/ui/viewer/file_details/backed_up_time_item_widget.dart';
import "package:photos/ui/viewer/file_details/creation_time_item_widget.dart";
import 'package:photos/ui/viewer/file_details/exif_item_widgets.dart';
import "package:photos/ui/viewer/file_details/file_info_faces_item_widget.dart";
import "package:photos/ui/viewer/file_details/file_info_pets_item_widget.dart";
import "package:photos/ui/viewer/file_details/file_properties_item_widget.dart";
import "package:photos/ui/viewer/file_details/location_tags_widget.dart";
import "package:photos/ui/viewer/file_details/preview_properties_item_widget.dart";
import "package:photos/ui/viewer/file_details/video_exif_item.dart";
import "package:photos/utils/exif_util.dart";
import "package:photos/utils/file_util.dart";

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
    final properties = await getVideoPropsAsync(originFile);
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

    //Make sure the bottom most tile is always the same one, that is it should
    //not be rendered only if a condition is met.
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
    fileDetailsTiles.addAll([
      CreationTimeItem(file, _currentUserID),
      const FileDetailsDivider(),
      ValueListenableBuilder(
        valueListenable: _exifNotifier,
        builder: (context, _, _) =>
            FilePropertiesItemWidget(file, _isImage, _exifData, _currentUserID),
      ),
      const FileDetailsDivider(),
      if (widget.file.uploadedFileID != null &&
          (fileDataService.previewIds.containsKey(
            widget.file.uploadedFileID,
          ))) ...[
        ValueListenableBuilder(
          valueListenable: _exifNotifier,
          builder: (context, _, _) => PreviewPropertiesItemWidget(
            file,
            _isImage,
            _exifData,
            _currentUserID,
          ),
        ),
        const FileDetailsDivider(),
      ],
    ]);
    fileDetailsTiles.add(
      ValueListenableBuilder(
        valueListenable: _exifNotifier,
        builder: (context, value, _) {
          return showExifListTile
              ? Column(
                  children: [
                    BasicExifItemWidget(_exifData),
                    const FileDetailsDivider(),
                  ],
                )
              : const SizedBox.shrink();
        },
      ),
    );

    fileDetailsTiles.addAll([
      ValueListenableBuilder(
        valueListenable: hasLocationData,
        builder: (context, bool value, _) {
          return value
              ? Column(
                  children: [
                    LocationTagsWidget(widget.file),
                    const FileDetailsDivider(),
                  ],
                )
              : const SizedBox.shrink();

          ///To be used when state issues are fixed when location is updated.
          //
          //  file.fileType != FileType.video &&
          //         file.ownerID == _currentUserID
          //     ? Column(
          //         children: [
          //           InfoItemWidget(
          //             leadingIcon: Icons.pin_drop_outlined,
          //             title: "No location data",
          //             subtitleSection: Future.value(
          //               [
          //                 Text(
          //                   "Add location data",
          //                   style: getEnteTextTheme(context).miniBoldMuted,
          //                 ),
          //               ],
          //             ),
          //             hasChipButtons: false,
          //             onTap: () async {
          //               await showBarModalBottomSheet(
          //                 shape: const RoundedRectangleBorder(
          //                   borderRadius: BorderRadius.vertical(
          //                     top: Radius.circular(5),
          //                   ),
          //                 ),
          //                 backgroundColor: getEnteColorScheme(context)
          //                     .backgroundElevated,
          //                 barrierColor: backdropFaintDark,
          //                 context: context,
          //                 builder: (context) {
          //                   return UpdateLocationDataWidget([file]);
          //                 },
          //               );
          //             },
          //           ),
          //           const FileDetailsDivider(),
          //         ],
          //       )
          //     : const SizedBox.shrink();
        },
      ),
    ]);
    if (_isImage) {
      fileDetailsTiles.addAll([
        ValueListenableBuilder(
          valueListenable: _exifNotifier,
          builder: (context, value, _) {
            return Column(
              children: [
                AllExifItemWidget(file, _exifNotifier.value),
                const FileDetailsDivider(),
              ],
            );
          },
        ),
      ]);
    } else if (widget.file.isVideo) {
      fileDetailsTiles.addAll([
        ValueListenableBuilder(
          valueListenable: _videoMetadataNotifier,
          builder: (context, value, _) {
            return Column(
              children: [
                VideoExifRowItem(file, value),
                const FileDetailsDivider(),
              ],
            );
          },
        ),
      ]);
    }

    if (hasGrantedMLConsent) {
      fileDetailsTiles.addAll([
        FacesItemWidget(file),
        const FileDetailsDivider(),
      ]);
      if (flagService.petEnabled && localSettings.petRecognitionEnabled) {
        fileDetailsTiles.addAll([
          PetsItemWidget(file),
          const FileDetailsDivider(),
        ]);
      }
    }

    if (file.uploadedFileID != null && file.updationTime != null) {
      fileDetailsTiles.addAll([
        BackedUpTimeItemWidget(file),
        const FileDetailsDivider(),
      ]);
    }
    if (!file.isTrash) {
      fileDetailsTiles.add(AlbumsItemWidget(file, _currentUserID));
    }

    return SafeArea(
      top: false,
      child: Scrollbar(
        thickness: 4,
        radius: const Radius.circular(2),
        thumbVisibility: true,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: CustomScrollView(
            controller: widget.scrollController,
            physics: const ClampingScrollPhysics(),
            shrinkWrap: true,
            slivers: <Widget>[
              TitleBarWidget(
                isFlexibleSpaceDisabled: true,
                title: AppLocalizations.of(context).details,
                isOnTopOfScreen: false,
                backgroundColor: getEnteColorScheme(context).backgroundElevated,
                leading: IconButtonWidget(
                  icon: Icons.expand_more_outlined,
                  iconButtonType: IconButtonType.primary,
                  onTap: () => Navigator.pop(context),
                ),
              ),
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

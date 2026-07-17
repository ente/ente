import "dart:convert";
import "dart:typed_data";

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/db/offline_files_db.dart";
import "package:photos/generated/intl/app_localizations.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/ml/face/box.dart";
import "package:photos/models/ml/face/detection.dart";
import "package:photos/models/ml/face/face.dart";
import "package:photos/service_locator.dart" show isLocalGalleryMode;
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/viewer/people/face_thumbnail_squircle.dart";
import "package:photos/ui/viewer/people/file_face_widget.dart";
import "package:photos/utils/face/face_thumbnail_cache.dart";

final Logger _logger = Logger("PetsItemWidget");

class PetsItemWidget extends StatefulWidget {
  final EnteFile file;
  const PetsItemWidget(this.file, {super.key});

  @override
  State<PetsItemWidget> createState() => _PetsItemWidgetState();
}

class _PetsItemWidgetState extends State<PetsItemWidget> {
  bool _isLoading = true;
  List<_PetFaceInfo> _petFaces = [];

  @override
  void initState() {
    super.initState();
    _loadPetFaces();
  }

  Future<void> _loadPetFaces() async {
    try {
      final bool isLocalGallery = isLocalGalleryMode;
      int? fileKey;
      if (isLocalGallery) {
        final localId = widget.file.localID;
        if (localId == null || localId.isEmpty) {
          if (mounted) setState(() => _isLoading = false);
          return;
        }
        fileKey = await OfflineFilesDB.instance.getOrCreateLocalIntId(localId);
      } else {
        fileKey = widget.file.uploadedFileID;
        if (fileKey == null) {
          if (mounted) setState(() => _isLoading = false);
          return;
        }
      }

      final mlDataDB = isLocalGallery
          ? MLDataDB.localGalleryInstance
          : MLDataDB.instance;
      final dbPetFaces = await mlDataDB.getPetFacesForFileID(fileKey);
      if (dbPetFaces == null || dbPetFaces.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Convert DBPetFace to Face objects for crop generation.
      // The detection JSON stores box as [xMin, yMin, xMax, yMax] (xyxy),
      // so we parse it into FaceBox(x, y, width, height) manually.
      final faces = <Face>[];
      for (final dbPetFace in dbPetFaces) {
        final json = jsonDecode(dbPetFace.detection) as Map<String, dynamic>;
        final boxList = (json['box'] as List)
            .map((e) => (e as num).toDouble())
            .toList();
        final detection = Detection(
          box: FaceBox(
            x: boxList[0],
            y: boxList[1],
            width: boxList[2] - boxList[0],
            height: boxList[3] - boxList[1],
          ),
          landmarks: const [],
        );
        faces.add(
          Face(
            dbPetFace.petFaceId,
            dbPetFace.fileId,
            const <double>[],
            dbPetFace.faceScore,
            detection,
            0.0,
          ),
        );
      }

      final faceCrops = await getCachedFaceCrops(
        widget.file,
        faces,
        useTempCache: true,
      );

      if (!mounted) return;
      if (faceCrops == null) {
        setState(() => _isLoading = false);
        return;
      }

      final petFaceInfos = <_PetFaceInfo>[];
      for (final dbPetFace in dbPetFaces) {
        final crop = faceCrops[dbPetFace.petFaceId];
        if (crop != null) {
          petFaceInfos.add(
            _PetFaceInfo(
              petFaceId: dbPetFace.petFaceId,
              species: dbPetFace.species,
              faceCrop: crop,
            ),
          );
        }
      }

      if (mounted) {
        setState(() {
          _petFaces = petFaceInfos;
          _isLoading = false;
        });
      }
    } catch (e, s) {
      _logger.severe("Failed to load pet faces", e, s);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoading && _petFaces.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xxl),
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Center(
          child: EnteLoadingWidget(
            padding: 6,
            size: 20,
            alignment: Alignment.center,
          ),
        ),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final thumbnailWidth = screenWidth * 0.16;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(AppLocalizations.of(context).discover_pets, style: TextStyles.h2),
        const SizedBox(height: Spacing.lg),
        Wrap(
          runSpacing: 8,
          spacing: 12,
          children: _petFaces
              .map((info) => _buildPetThumbnail(info, thumbnailWidth))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildPetThumbnail(_PetFaceInfo info, double thumbnailWidth) {
    final l10n = AppLocalizations.of(context);
    final speciesLabel = info.species == 0 ? l10n.dog : l10n.cat;

    return SizedBox(
      width: thumbnailWidth,
      child: Column(
        children: [
          SizedBox(
            height: thumbnailWidth,
            width: thumbnailWidth,
            child: FaceThumbnailSquircleClip(
              child: FileFaceWidget(widget.file, faceCrop: info.faceCrop),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            speciesLabel,
            style: TextStyles.mini,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

class _PetFaceInfo {
  final String petFaceId;
  final int species;
  final Uint8List faceCrop;

  _PetFaceInfo({
    required this.petFaceId,
    required this.species,
    required this.faceCrop,
  });
}

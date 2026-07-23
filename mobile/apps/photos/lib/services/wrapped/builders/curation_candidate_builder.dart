part of 'package:photos/services/wrapped/candidate_builders.dart';

class CurationCandidateBuilder extends WrappedCandidateBuilder {
  const CurationCandidateBuilder();

  static const int _kMinFavoritesForCard = 6;
  static const int _kGalleryGroupSize = 6;
  static const int _kMaxGalleryGroups = 3;
  static const int _kRotationMillis = 2400;

  @override
  String get debugLabel => "curation";

  @override
  Future<List<WrappedCard>> build(WrappedEngineContext context) async {
    final Set<int> favoriteIds = context.favoriteUploadedFileIDs;
    if (favoriteIds.length < _kMinFavoritesForCard) {
      return const <WrappedCard>[];
    }

    final List<EnteFile> favoriteFiles = context.files
        .where(
          (EnteFile file) =>
              file.uploadedFileID != null &&
              favoriteIds.contains(file.uploadedFileID),
        )
        .toList(growable: false);
    if (favoriteFiles.length < _kMinFavoritesForCard) {
      return const <WrappedCard>[];
    }

    final List<EnteFile> displayableFavorites = favoriteFiles
        .where((EnteFile file) {
          if (file.magicMetadata.visibility == archiveVisibility) {
            return false;
          }
          final int? collectionID = file.collectionID;
          if (collectionID != null &&
              context.archivedCollectionIDs.contains(collectionID)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
    if (displayableFavorites.length < _kMinFavoritesForCard) {
      return const <WrappedCard>[];
    }

    final math.Random randomizer = math.Random(
      context.year * 53 + displayableFavorites.length,
    );
    final List<List<int>> galleryGroups = _buildGalleryGroups(
      displayableFavorites,
      randomizer,
    );
    if (galleryGroups.isEmpty) {
      return const <WrappedCard>[];
    }

    final List<int> uploadedIds = displayableFavorites
        .map((EnteFile file) => file.uploadedFileID)
        .whereType<int>()
        .toList(growable: false);
    if (uploadedIds.length < _kMinFavoritesForCard) {
      return const <WrappedCard>[];
    }

    final Set<int> seenHeroIds = <int>{};
    final List<int> heroCandidates = <int>[];
    final int extendedLimit = math.min(
      uploadedIds.length,
      kWrappedSelectorCandidateCap,
    );

    for (final List<int> group in galleryGroups) {
      for (final int id in group) {
        if (id <= 0 || !seenHeroIds.add(id)) {
          continue;
        }
        heroCandidates.add(id);
        if (heroCandidates.length >= extendedLimit) {
          break;
        }
      }
      if (heroCandidates.length >= extendedLimit) {
        break;
      }
    }

    if (heroCandidates.length < extendedLimit) {
      for (final int id in uploadedIds) {
        if (heroCandidates.length >= extendedLimit) {
          break;
        }
        if (id <= 0 || !seenHeroIds.add(id)) {
          continue;
        }
        heroCandidates.add(id);
      }
    }

    if (heroCandidates.length < _kGalleryGroupSize) {
      return const <WrappedCard>[];
    }

    final List<MediaRef> heroMedia = WrappedMediaSelector.selectMediaRefs(
      context: context,
      candidateUploadedFileIDs: heroCandidates,
      maxCount: math.min(_kGalleryGroupSize, heroCandidates.length),
      preferNamedPeople: true,
      minimumSpacing: const Duration(days: 30),
    );

    if (heroMedia.length < _kGalleryGroupSize) {
      return const <WrappedCard>[];
    }

    final NumberFormat numberFormat = NumberFormat.decimalPattern();
    final int favoritesCount = favoriteFiles.length;
    final int totalCount = context.files.length;
    final int sharePercent = totalCount <= 0
        ? 0
        : _percentOf(favoritesCount / totalCount);

    final List<String> chips = _cleanChips(<String>[
      "Favorites: ${numberFormat.format(favoritesCount)}",
      if (sharePercent > 0) "Share: $sharePercent%",
    ]);

    final Map<String, Object?> meta = <String, Object?>{
      "favoriteCount": favoritesCount,
      "totalCount": totalCount,
      "sharePercent": sharePercent,
      "detailChips": chips,
      "galleryGroups": galleryGroups
          .map((List<int> group) => group.toList(growable: false))
          .toList(growable: false),
      "rotationMillis": _kRotationMillis,
      "displayDurationMillis": 18000,
    };

    final String subtitle = favoritesCount == 1
        ? "You kept one standout starred for safekeeping."
        : "You handpicked ${numberFormat.format(favoritesCount)} favorites to keep close.";

    final WrappedCard favoritesCard = WrappedCard(
      type: WrappedCardType.favorites,
      title: "Your favorites",
      subtitle: subtitle,
      media: heroMedia,
      meta: meta,
    );

    return <WrappedCard>[favoritesCard];
  }

  List<List<int>> _buildGalleryGroups(
    List<EnteFile> favoriteFiles,
    math.Random randomizer,
  ) {
    final List<int> uploadedIds = favoriteFiles
        .map((EnteFile file) => file.uploadedFileID)
        .whereType<int>()
        .toList(growable: false);
    if (uploadedIds.length < _kMinFavoritesForCard) {
      return const <List<int>>[];
    }

    final List<int> indices = List<int>.generate(
      uploadedIds.length,
      (int index) => index,
    );
    _shuffle(indices, randomizer);

    final int maxUsable = math.min(
      uploadedIds.length,
      _kGalleryGroupSize * _kMaxGalleryGroups,
    );
    final int groupCount = maxUsable ~/ _kGalleryGroupSize;
    final List<List<int>> groups = <List<int>>[];

    if (groupCount == 0) {
      final List<int> fallback = indices
          .take(_kGalleryGroupSize)
          .map((int index) => uploadedIds[index])
          .toList(growable: false);
      if (fallback.length >= _kMinFavoritesForCard) {
        groups.add(fallback);
      }
      return groups;
    }

    int cursor = 0;
    for (int i = 0; i < groupCount; i += 1) {
      final List<int> group = <int>[];
      for (int j = 0; j < _kGalleryGroupSize; j += 1) {
        final int index = indices[cursor++];
        group.add(uploadedIds[index]);
      }
      groups.add(group);
    }

    return groups
        .map((List<int> group) => group.toList(growable: false))
        .toList(growable: false);
  }

  void _shuffle<T>(List<T> list, math.Random randomizer) {
    for (int i = list.length - 1; i > 0; i -= 1) {
      final int j = randomizer.nextInt(i + 1);
      final T temp = list[i];
      list[i] = list[j];
      list[j] = temp;
    }
  }
}

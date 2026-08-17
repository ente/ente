import "dart:async";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/collection_updated_event.dart";
import "package:photos/events/contact_relationships_invalidated_event.dart";
import "package:photos/events/contacts_changed_event.dart";
import "package:photos/events/event.dart";
import "package:photos/events/location_tag_updated_event.dart";
import "package:photos/events/magic_cache_updated_event.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/collection/collection_items.dart";
import "package:photos/models/search/search_result.dart";
import "package:photos/models/typedefs.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/machine_learning/face_ml/face_filtering/face_filtering_constants.dart";
import "package:photos/services/search_service.dart";
import "package:photos/ui/viewer/gallery/collection_page.dart";
import "package:photos/ui/viewer/location/add_location_sheet.dart";
import "package:photos/ui/viewer/location/pick_center_point_widget.dart";
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/share_util.dart";

const _kSearchPreviewFallbackClusterSize = 3;

enum ResultType {
  collection,
  deviceCollection,
  file,
  uploader,
  location,
  locationSuggestion,
  month,
  year,
  fileType,
  fileExtension,
  fileCaption,
  event,
  shared,
  faces,
  magic,
  cameraMake,
  cameraModel,
}

enum SectionType {
  face,
  ritual,
  magic,
  wrapped,
  location,
  album,
  contacts,
  fileTypesAndExtension,
}

extension SectionTypeExtensions on SectionType {
  String sectionTitle(BuildContext context) {
    switch (this) {
      case SectionType.face:
        return context.strings.people;
      case SectionType.magic:
        return context.strings.discover;
      case SectionType.wrapped:
        return "Ente Rewind";
      case SectionType.location:
        return context.strings.locations;
      case SectionType.ritual:
        return context.strings.ritualsTitle;
      case SectionType.contacts:
        return context.strings.contacts;
      case SectionType.album:
        return context.strings.albums;
      case SectionType.fileTypesAndExtension:
        return context.strings.fileTypes;
    }
  }

  String getEmptyStateText(BuildContext context) {
    switch (this) {
      case SectionType.face:
        return context.strings.searchPersonsEmptySection;
      case SectionType.magic:
        return context.strings.searchDiscoverEmptySection;
      case SectionType.wrapped:
        return "Check back soon for your 2025 highlights.";
      case SectionType.location:
        return context.strings.searchLocationEmptySection;
      case SectionType.ritual:
        return context.strings.ritualSearchEmpty;
      case SectionType.contacts:
        return context.strings.searchPeopleEmptySection;
      case SectionType.album:
        return context.strings.searchAlbumsEmptySection;
      case SectionType.fileTypesAndExtension:
        return context.strings.searchFileTypesAndNamesEmptySection;
    }
  }

  bool get isCTAVisible {
    switch (this) {
      case SectionType.face:
      case SectionType.magic:
      case SectionType.wrapped:
      case SectionType.ritual:
      case SectionType.fileTypesAndExtension:
        return false;
      case SectionType.location:
      case SectionType.contacts:
      case SectionType.album:
        return true;
    }
  }

  bool get sortByName =>
      this != SectionType.face &&
      this != SectionType.magic &&
      this != SectionType.wrapped &&
      this != SectionType.ritual &&
      this != SectionType.contacts;

  bool get isEmptyCTAVisible {
    switch (this) {
      case SectionType.face:
      case SectionType.magic:
      case SectionType.wrapped:
      case SectionType.ritual:
      case SectionType.fileTypesAndExtension:
        return false;
      case SectionType.location:
      case SectionType.contacts:
      case SectionType.album:
        return true;
    }
  }

  String getCTAText(BuildContext context) {
    switch (this) {
      case SectionType.face:
        // todo: later
        return "Setup";
      case SectionType.magic:
        // todo: later
        return "temp";
      case SectionType.wrapped:
        return "";
      case SectionType.location:
        return context.strings.addNew;
      case SectionType.ritual:
        return "";
      case SectionType.contacts:
        return context.strings.invite;
      case SectionType.album:
        return context.strings.addNew;
      case SectionType.fileTypesAndExtension:
        return "";
    }
  }

  IconData? getCTAIcon() {
    switch (this) {
      case SectionType.face:
        return Icons.adaptive.arrow_forward_outlined;
      case SectionType.magic:
        return null;
      case SectionType.wrapped:
        return null;
      case SectionType.location:
        return Icons.add_location_alt_outlined;
      case SectionType.ritual:
        return null;
      case SectionType.contacts:
        return Icons.adaptive.share;
      case SectionType.album:
        return Icons.add;
      case SectionType.fileTypesAndExtension:
        return null;
    }
  }

  FutureVoidCallback ctaOnTap(BuildContext context) {
    switch (this) {
      case SectionType.contacts:
        return () async {
          await shareText(context.strings.shareTextRecommendUsingEnteForPhotos);
        };
      case SectionType.location:
        return () async {
          final centerPoint = await showPickCenterPointSheet(context);
          if (centerPoint != null) {
            if (!context.mounted) return;
            showAddLocationSheet(context, centerPoint);
          }
        };
      case SectionType.ritual:
        return () async {};
      case SectionType.album:
        return () async {
          final result = await showTextInputDialog(
            context,
            title: context.strings.newAlbum,
            submitButtonLabel: context.strings.create,
            hintText: context.strings.enterAlbumName,
            alwaysShowSuccessState: false,
            initialValue: "",
            textCapitalization: TextCapitalization.words,
            onSubmit: (String text) async {
              if (text.trim() == "") {
                return;
              }
              try {
                final Collection c = await CollectionsService.instance
                    .createAlbum(text);

                // Close now so it does not flash when returning from the album.
                if (!context.mounted) return;
                Navigator.of(context).pop();

                if (!context.mounted) return;
                // ignore: unawaited_futures
                await routeToPage(
                  context,
                  CollectionPage(CollectionWithThumbnail(c, null)),
                );
              } catch (e, s) {
                Logger(
                  "CreateNewAlbumIcon",
                ).severe("Failed to create a new album", e, s);
                rethrow;
              }
            },
          );
          if (result is Exception) {
            if (!context.mounted) return;
            await showGenericErrorDialog(context: context, error: result);
          }
        };
      case SectionType.wrapped:
        return () async {};
      default:
        {
          return () async {};
        }
    }
  }

  Future<List<SearchResult>> getData(BuildContext? context, {int? limit}) {
    switch (this) {
      case SectionType.face:
        return SearchService.instance.getAllFace(
          limit,
          minClusterSize: limit == null
              ? kMinimumClusterSizeAllFaces
              : kMinimumClusterSizeSearchResult,
          fallbackMinClusterSize: limit == null
              ? null
              : _kSearchPreviewFallbackClusterSize,
        );
      case SectionType.magic:
        return SearchService.instance.getMagicSectionResults(
          context!,
          limit: limit,
        );
      case SectionType.wrapped:
        return Future.value(const <SearchResult>[]);
      case SectionType.location:
        return SearchService.instance.getAllLocationTags(limit);
      case SectionType.ritual:
        return Future.value(const <SearchResult>[]);

      case SectionType.contacts:
        return SearchService.instance.getAllContactsSearchResults(limit);

      case SectionType.album:
        return SearchService.instance.getAllCollectionSearchResults(limit);

      case SectionType.fileTypesAndExtension:
        return SearchService.instance.getAllFileTypesAndExtensionsResults(
          context!,
          limit,
        );
    }
  }

  List<Stream<Event>> viewAllUpdateEvents() {
    switch (this) {
      case SectionType.location:
        return [Bus.instance.on<LocationTagUpdatedEvent>()];
      case SectionType.wrapped:
        return [];
      case SectionType.ritual:
        return [];
      case SectionType.album:
        return [Bus.instance.on<CollectionUpdatedEvent>()];
      case SectionType.face:
        return [Bus.instance.on<PeopleChangedEvent>()];
      case SectionType.contacts:
        return [
          Bus.instance.on<ContactRelationshipsInvalidatedEvent>(),
          Bus.instance.on<PeopleChangedEvent>(),
          Bus.instance.on<ContactsChangedEvent>(),
        ];
      default:
        return [];
    }
  }

  List<Stream<Event>> sectionUpdateEvents() {
    switch (this) {
      case SectionType.location:
        return [Bus.instance.on<LocationTagUpdatedEvent>()];
      case SectionType.magic:
        return [Bus.instance.on<MagicCacheUpdatedEvent>()];
      case SectionType.wrapped:
        return [];
      case SectionType.ritual:
        return [];
      case SectionType.contacts:
        return [
          Bus.instance.on<ContactRelationshipsInvalidatedEvent>(),
          Bus.instance.on<PeopleChangedEvent>(),
          Bus.instance.on<ContactsChangedEvent>(),
        ];
      default:
        return [];
    }
  }
}

import "dart:async";

import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:photos/core/event_bus.dart';
import "package:photos/events/collection_meta_event.dart";
import "package:photos/events/collection_updated_event.dart";
import "package:photos/events/files_updated_event.dart";
import 'package:photos/events/force_reload_home_gallery_event.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/file/file.dart';
import "package:photos/models/metadata/collection_magic.dart";
import "package:photos/models/metadata/common_keys.dart";
import "package:photos/models/metadata/file_magic.dart";
import 'package:photos/service_locator.dart' show librarySharingService;
import 'package:photos/services/collections_service.dart';
import 'package:photos/services/file_magic_service.dart';
import 'package:photos/ui/common/progress_dialog.dart';
import 'package:photos/ui/components/buttons/button_widget.dart';
import 'package:photos/ui/components/models/button_type.dart';
import 'package:photos/ui/notification/toast.dart';
import 'package:photos/utils/dialog_util.dart';

final _logger = Logger('MagicUtil');

enum _VisibilityAction { hide, unHide, archive, unarchive }

Future<void> changeVisibility(
  BuildContext context,
  List<EnteFile> files,
  int newVisibility,
) async {
  final dialog = createProgressDialog(
    context,
    newVisibility == archiveVisibility
        ? context.strings.archiving
        : context.strings.unarchiving,
  );
  await dialog.show();
  try {
    await FileMagicService.instance.changeVisibility(files, newVisibility);
    await dialog.hide();
    if (context.mounted) {
      showShortToast(
        context,
        newVisibility == archiveVisibility
            ? context.strings.successfullyArchived
            : context.strings.successfullyUnarchived,
      );
    }
  } catch (e, s) {
    _logger.severe("failed to update file visibility", e, s);
    await dialog.hide();
    rethrow;
  }
}

Future<void> changeCollectionVisibility(
  BuildContext context, {
  required Collection collection,
  required int newVisibility,
  required int prevVisibility,
  bool isOwner = true,
  bool showProgressDialog = true,
  bool skipSharedAlbumWarning = false,
}) async {
  if (isOwner &&
      !skipSharedAlbumWarning &&
      newVisibility == hiddenVisibility &&
      prevVisibility != hiddenVisibility &&
      !await prepareSharedAlbumsForHiding(context, [collection])) {
    return;
  }
  if (!context.mounted) return;
  final visibilityAction = _getVisibilityAction(
    context,
    newVisibility,
    prevVisibility,
  );
  ProgressDialog? dialog;
  if (showProgressDialog) {
    dialog = createProgressDialog(
      context,
      _visActionProgressDialogText(context, visibilityAction),
    );
    await dialog.show();
  }

  try {
    final Map<String, dynamic> update = {magicKeyVisibility: newVisibility};
    if (isOwner) {
      await CollectionsService.instance.updateMagicMetadata(collection, update);
      Bus.instance.fire(
        CollectionUpdatedEvent(
          collection.id,
          const <EnteFile>[],
          'collection_visibility_changed',
        ),
      );
    } else {
      await CollectionsService.instance.updateShareeMagicMetadata(
        collection,
        update,
      );
    }
    // Reload so the home gallery adds or removes the collection's files.
    Bus.instance.fire(
      ForceReloadHomeGalleryEvent(
        "CollectionVisibilityChange: $visibilityAction",
      ),
    );
    await dialog?.hide();
    if (showProgressDialog && context.mounted) {
      showShortToast(
        context,
        _visActionSuccessfulText(context, visibilityAction),
      );
    }
  } catch (e, s) {
    _logger.severe("failed to update collection visibility", e, s);
    await dialog?.hide();
    rethrow;
  }
}

Future<bool> prepareSharedAlbumsForHiding(
  BuildContext context,
  Iterable<Collection> collections,
) async {
  final sharedAlbums = collections
      .where((collection) => collection.hasSharees)
      .toList();
  if (sharedAlbums.isEmpty) {
    return true;
  }
  final result = await showChoiceDialog(
    context,
    title: context.strings.warning,
    body: pendingTranslation(
      sharedAlbums.length == 1
          ? 'This album is currently being shared. Please unshare if you wish to hide its contents from receivers.'
          : 'Some selected albums are currently being shared. Please unshare if you wish to hide their contents from receivers.',
    ),
    firstButtonLabel: context.strings.hide,
    secondButtonLabel: pendingTranslation('Unshare and Hide'),
    firstButtonType: ButtonType.neutral,
    secondButtonType: ButtonType.critical,
    secondButtonAction: ButtonAction.second,
    icon: Icons.warning_amber_rounded,
  );
  if (result?.action == ButtonAction.first) {
    return true;
  }
  if (result?.action != ButtonAction.second || !context.mounted) {
    return false;
  }

  final dialog = createProgressDialog(context, context.strings.pleaseWait);
  await dialog.show();
  try {
    for (final album in sharedAlbums) {
      await librarySharingService.unshareAlbumFromAll(album);
    }
    await dialog.hide();
    return context.mounted;
  } catch (error, stackTrace) {
    _logger.warning(
      'Failed to unshare albums before hiding',
      error,
      stackTrace,
    );
    await dialog.hide();
    if (context.mounted) {
      await showGenericErrorDialog(context: context, error: error);
    }
    return false;
  }
}

Future<void> changeSortOrder(
  BuildContext context,
  Collection collection,
  bool sortedInAscOrder,
) async {
  try {
    final Map<String, dynamic> update = {"asc": sortedInAscOrder};
    await CollectionsService.instance.updatePublicMagicMetadata(
      collection,
      update,
    );
    Bus.instance.fire(
      CollectionMetaEvent(collection.id, CollectionMetaEventType.sortChanged),
    );
  } catch (e, s) {
    _logger.severe("failed to update collection visibility", e, s);
    if (context.mounted) {
      showShortToast(context, context.strings.somethingWentWrong);
    }
    rethrow;
  }
}

Future<void> updateOrder(
  BuildContext context,
  Collection collection,
  int order,
) async {
  try {
    final Map<String, dynamic> update = {orderKey: order};
    await CollectionsService.instance.updateMagicMetadata(collection, update);
    Bus.instance.fire(
      CollectionMetaEvent(collection.id, CollectionMetaEventType.orderChanged),
    );
  } catch (e, s) {
    _logger.severe("failed to update order", e, s);
    if (context.mounted) {
      showShortToast(context, context.strings.somethingWentWrong);
    }
    rethrow;
  }
}

Future<void> updateShareeOrder(
  BuildContext context,
  Collection collection,
  int order,
) async {
  try {
    final Map<String, dynamic> update = {orderKey: order};
    await CollectionsService.instance.updateShareeMagicMetadata(
      collection,
      update,
    );
    Bus.instance.fire(
      CollectionMetaEvent(collection.id, CollectionMetaEventType.orderChanged),
    );
  } catch (e, s) {
    _logger.severe("failed to update sharee order", e, s);
    if (context.mounted) {
      showShortToast(context, context.strings.somethingWentWrong);
    }
    rethrow;
  }
}

// Pass 0 to restore the default cover.
Future<void> changeCoverPhoto(
  BuildContext context,
  Collection collection,
  int uploadedFileID,
) async {
  try {
    final Map<String, dynamic> update = {"coverID": uploadedFileID};
    await CollectionsService.instance.updatePublicMagicMetadata(
      collection,
      update,
    );
    Bus.instance.fire(
      CollectionUpdatedEvent(
        collection.id,
        <EnteFile>[],
        "cover_change",
        type: EventType.coverChanged,
      ),
    );
  } catch (e, s) {
    _logger.severe("failed to update cover", e, s);
    if (context.mounted) {
      showShortToast(context, context.strings.somethingWentWrong);
    }
    rethrow;
  }
}

Future<void> changeAlbumDescription(
  BuildContext context,
  Collection collection,
  String description,
) async {
  final normalizedDescription = description.trim();
  try {
    if (normalizedDescription.characters.length > maxAlbumDescriptionLength) {
      throw ArgumentError.value(
        description,
        "description",
        "Album descriptions cannot exceed $maxAlbumDescriptionLength characters",
      );
    }
    await CollectionsService.instance.updatePublicMagicMetadata(collection, {
      albumDescriptionKey: normalizedDescription,
    });
    Bus.instance.fire(
      CollectionUpdatedEvent(collection.id, <EnteFile>[], "description_change"),
    );
  } catch (e, s) {
    _logger.severe("failed to update album description", e, s);
    if (context.mounted) {
      showShortToast(context, context.strings.somethingWentWrong);
    }
    rethrow;
  }
}

Future<bool> editTime(
  BuildContext context,
  Map<EnteFile, int> filesToEditedTimes,
) async {
  try {
    final files = filesToEditedTimes.keys
        .where((file) => file.uploadedFileID != null)
        .toList();
    if (files.isEmpty) {
      _logger.severe('No files to edit time for');
      return false;
    }
    final fileIdToTimeUpdate = <int, Map<String, dynamic>>{};
    for (final entry in filesToEditedTimes.entries) {
      final file = entry.key;
      if (file.uploadedFileID == null) continue;
      final editedTime = entry.value;
      fileIdToTimeUpdate[file.uploadedFileID!] = {
        editTimeKey: editedTime,
        dateTimeKey: formatPubMagicDateTime(
          DateTime.fromMicrosecondsSinceEpoch(editedTime),
        ),
      };
    }

    final dialog = createProgressDialog(context, context.strings.pleaseWait);
    await dialog.show();
    try {
      await FileMagicService.instance.updatePublicMagicMetadata(
        files,
        null,
        metadataUpdateMap: fileIdToTimeUpdate,
      );
      if (_shouldReloadGallery(editTimeKey)) {
        Bus.instance.fire(
          ForceReloadHomeGalleryEvent("FileMetadataChange-$editTimeKey"),
        );
      }
      await dialog.hide();
      if (context.mounted) {
        showShortToast(context, context.strings.done);
      }
    } catch (e, s) {
      _logger.severe("failed to update times $fileIdToTimeUpdate", e, s);
      await dialog.hide();
      rethrow;
    }
    return true;
  } catch (e) {
    if (!context.mounted) return false;
    showShortToast(context, context.strings.somethingWentWrong);
    return false;
  }
}

Future<void> editFilename(BuildContext context, EnteFile file) async {
  final fileName = file.displayName;
  final nameWithoutExt = basenameWithoutExtension(fileName);
  final extName = extension(fileName);
  final result = await showTextInputDialog(
    context,
    title: context.strings.renameFile,
    submitButtonLabel: context.strings.rename,
    initialValue: nameWithoutExt,
    message: extName.toUpperCase(),
    alignMessage: Alignment.centerRight,
    hintText: context.strings.enterFileName,
    maxLength: 50,
    alwaysShowSuccessState: true,
    onSubmit: (String text) async {
      if (text.isEmpty || text.trim() == nameWithoutExt.trim()) {
        return;
      }
      final newName = text + extName;
      await _updatePublicMetadata(
        context,
        List.of([file]),
        editNameKey,
        newName,
        showProgressDialogs: false,
        showDoneToast: false,
      );
    },
  );
  if (result is Exception) {
    _logger.severe("Failed to rename file");
    if (!context.mounted) return;
    await showGenericErrorDialog(context: context, error: result);
  }
}

Future<bool> editFileCaption(
  BuildContext? context,
  EnteFile file,
  String caption,
) async {
  try {
    await _updatePublicMetadata(
      context,
      [file],
      captionKey,
      caption,
      showDoneToast: false,
    );

    return true;
  } catch (e) {
    return false;
  }
}

Future<void> _updatePublicMetadata(
  BuildContext? context,
  List<EnteFile> files,
  String key,
  dynamic value, {
  bool showDoneToast = true,
  bool showProgressDialogs = true,
}) async {
  if (files.isEmpty) {
    return;
  }
  ProgressDialog? dialog;
  if (context != null && showProgressDialogs) {
    dialog = createProgressDialog(context, context.strings.pleaseWait);
    await dialog.show();
  }
  try {
    final Map<String, dynamic> update = {key: value};
    await FileMagicService.instance.updatePublicMagicMetadata(files, update);
    if (context != null) {
      await dialog?.hide();
      if (showDoneToast && context.mounted) {
        showShortToast(context, context.strings.done);
      }
    }

    if (_shouldReloadGallery(key)) {
      Bus.instance.fire(ForceReloadHomeGalleryEvent("FileMetadataChange-$key"));
    }
  } catch (e, s) {
    _logger.severe("failed to update $key = $value", e, s);
    if (context != null) {
      await dialog?.hide();
    }
    rethrow;
  }
}

bool _shouldReloadGallery(String key) {
  return key == editTimeKey;
}

String _visActionProgressDialogText(
  BuildContext context,
  _VisibilityAction action,
) {
  switch (action) {
    case _VisibilityAction.archive:
      return context.strings.archiving;
    case _VisibilityAction.hide:
      return context.strings.hiding;
    case _VisibilityAction.unarchive:
      return context.strings.unarchiving;
    case _VisibilityAction.unHide:
      return context.strings.unhiding;
  }
}

String _visActionSuccessfulText(
  BuildContext context,
  _VisibilityAction action,
) {
  switch (action) {
    case _VisibilityAction.archive:
      return context.strings.successfullyArchived;
    case _VisibilityAction.hide:
      return context.strings.successfullyHid;
    case _VisibilityAction.unarchive:
      return context.strings.successfullyUnarchived;
    case _VisibilityAction.unHide:
      return context.strings.successfullyUnhid;
  }
}

_VisibilityAction _getVisibilityAction(
  BuildContext context,
  int newVisibility,
  int prevVisibility,
) {
  if (newVisibility == archiveVisibility) {
    return _VisibilityAction.archive;
  } else if (newVisibility == hiddenVisibility) {
    return _VisibilityAction.hide;
  } else if (newVisibility == visibleVisibility &&
      prevVisibility == archiveVisibility) {
    return _VisibilityAction.unarchive;
  } else {
    return _VisibilityAction.unHide;
  }
}

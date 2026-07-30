import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:flutter/foundation.dart";
import 'package:flutter/material.dart';
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/events/collection_updated_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/collection/smart_album_config.dart";
import "package:photos/models/selected_people.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/ui/actions/collection/collection_sharing_actions.dart";
import "package:photos/ui/components/action_sheet_widget.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/ui/viewer/search/result/people_section_all_page.dart"
    show PeopleSectionAllWidget;
import "package:photos/utils/dialog_util.dart";

class SmartAlbumPeople extends StatefulWidget {
  const SmartAlbumPeople({super.key, required this.collectionId});

  final int collectionId;

  @override
  State<SmartAlbumPeople> createState() => _SmartAlbumPeopleState();
}

class _SmartAlbumPeopleState extends State<SmartAlbumPeople> {
  final _selectedPeople = SelectedPeople();
  SmartAlbumConfig? currentConfig;

  final _logger = Logger("SmartAlbumPeople");

  @override
  void initState() {
    super.initState();
    getSelections();
  }

  Future<void> getSelections() async {
    currentConfig = await smartAlbumsService.getConfig(widget.collectionId);

    if (currentConfig != null &&
        currentConfig!.personIDs.isNotEmpty &&
        mounted) {
      _selectedPeople.select(currentConfig!.personIDs);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          8 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: ListenableBuilder(
          listenable: _selectedPeople,
          builder: (context, _) {
            final areIdsChanged = currentConfig?.personIDs != null
                ? !setEquals(
                    _selectedPeople.personIds,
                    currentConfig!.personIDs,
                  )
                : _selectedPeople.personIds.isNotEmpty;
            return ButtonComponent(
              variant: ButtonComponentVariant.primary,
              label: AppLocalizations.of(context).save,
              shouldSurfaceExecutionStates: false,
              isDisabled: !areIdsChanged,
              onTap: areIdsChanged
                  ? () async {
                      final dialog = createProgressDialog(
                        context,
                        AppLocalizations.of(context).pleaseWait,
                        isDismissible: true,
                      );

                      if (_selectedPeople.personIds.length ==
                              currentConfig?.personIDs.length &&
                          _selectedPeople.personIds
                              .toSet()
                              .difference(
                                currentConfig?.personIDs.toSet() ?? {},
                              )
                              .isEmpty) {
                        Navigator.pop(context);
                        return;
                      }

                      try {
                        await dialog.show();
                        SmartAlbumConfig newConfig;

                        if (currentConfig == null) {
                          final infoMap = <String, PersonInfo>{};

                          // Add files which are needed
                          for (final personId in _selectedPeople.personIds) {
                            infoMap[personId] = (updatedAt: 0, addedFiles: {});
                          }

                          newConfig = SmartAlbumConfig(
                            collectionId: widget.collectionId,
                            personIDs: _selectedPeople.personIds,
                            infoMap: infoMap,
                          );
                        } else {
                          final removedPersonIds = currentConfig!.personIDs
                              .toSet()
                              .difference(_selectedPeople.personIds.toSet())
                              .toList();

                          if (removedPersonIds.isNotEmpty) {
                            if (!context.mounted) return;
                            final toDelete = await removeFilesDialog(context);
                            await dialog.show();

                            if (toDelete) {
                              for (final personId in removedPersonIds) {
                                final files = currentConfig!
                                    .infoMap[personId]
                                    ?.addedFiles;

                                final enteFiles = await FilesDB.instance
                                    .getAllFilesGroupByCollectionID(
                                      files?.toList() ?? [],
                                    );

                                final collection = CollectionsService.instance
                                    .getCollectionByID(widget.collectionId);

                                if (files?.isNotEmpty ?? false) {
                                  await CollectionActions(
                                    CollectionsService.instance,
                                  ).moveFilesFromCurrentCollection(
                                    null,
                                    collection!,
                                    enteFiles[widget.collectionId] ?? [],
                                    isHidden: collection.isHidden(),
                                  );
                                }
                              }

                              Bus.instance.fire(
                                CollectionUpdatedEvent(
                                  widget.collectionId,
                                  [],
                                  "smart_album_people",
                                ),
                              );
                            }
                          }
                          newConfig = currentConfig!.getUpdatedConfig(
                            _selectedPeople.personIds,
                          );
                        }

                        await smartAlbumsService.saveConfig(newConfig);
                        unawaited(smartAlbumsService.syncSmartAlbums());

                        await dialog.hide();
                        if (!context.mounted) return;
                        Navigator.pop(context);
                      } catch (error, stackTrace) {
                        _logger.severe(
                          "Error saving smart album config",
                          error,
                          stackTrace,
                        );
                        await dialog.hide();
                        if (!context.mounted) return;
                        await showGenericErrorDialog(
                          context: context,
                          error: error,
                        );
                      }
                    }
                  : null,
            );
          },
        ),
      ),
      body: AppBarComponent(
        title: AppLocalizations.of(context).people,
        subtitle: AppLocalizations.of(context).peopleAutoAddDesc,
        physics: const BouncingScrollPhysics(),
        slivers: <Widget>[
          SliverFillRemaining(
            child: PeopleSectionAllWidget(
              selectedPeople: _selectedPeople,
              namedOnly: true,
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> removeFilesDialog(BuildContext context) async {
  final completer = Completer<bool>();
  await showActionSheet(
    context: context,
    body: AppLocalizations.of(context).shouldRemoveFilesSmartAlbumsDesc,
    buttons: [
      ButtonWidget(
        labelText: AppLocalizations.of(context).yes,
        buttonType: ButtonType.neutral,
        buttonSize: ButtonSize.large,
        shouldStickToDarkTheme: true,
        buttonAction: ButtonAction.first,
        shouldSurfaceExecutionStates: true,
        isInAlert: true,
        onTap: () async {
          completer.complete(true);
        },
      ),
      ButtonWidget(
        labelText: AppLocalizations.of(context).no,
        buttonType: ButtonType.secondary,
        buttonSize: ButtonSize.large,
        shouldStickToDarkTheme: true,
        buttonAction: ButtonAction.cancel,
        isInAlert: true,
        onTap: () async {
          completer.complete(false);
        },
      ),
    ],
  );

  return completer.future;
}

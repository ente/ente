import "dart:async";

import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/models/typedefs.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/people/face_thumbnail_squircle.dart";
import "package:photos/ui/viewer/people/person_face_widget.dart";
import "package:photos/utils/dialog_util.dart";

class ReassignMeSelectionPage extends StatefulWidget {
  final String currentMeId;
  const ReassignMeSelectionPage({required this.currentMeId, super.key});

  @override
  State<ReassignMeSelectionPage> createState() =>
      _ReassignMeSelectionPageState();
}

class _ReassignMeSelectionPageState extends State<ReassignMeSelectionPage> {
  late Future<List<PersonEntity>> _personEntities;
  final _logger = Logger('ReassignMeSelectionPage');

  @override
  void initState() {
    super.initState();

    _personEntities = PersonService.instance.getPersons().then((persons) async {
      final List<PersonEntity> result = [];
      for (final person in persons) {
        if (person.data.userID != null ||
            (person.data.email != null && person.data.email!.isNotEmpty) ||
            (person.data.isIgnored)) {
          continue;
        }
        result.add(person);
      }
      return result;
    });
  }

  @override
  Widget build(BuildContext context) {
    _logger.info("Building ReassignMeSelectionPage");
    final smallFontSize = getEnteTextTheme(context).small.fontSize!;
    final textScaleFactor =
        MediaQuery.textScalerOf(context).scale(smallFontSize) / smallFontSize;
    const horizontalEdgePadding = 20.0;
    const gridPadding = 16.0;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.selectYourFace),
        centerTitle: false,
      ),
      body: FutureBuilder<List<PersonEntity>>(
        future: _personEntities,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: EnteLoadingWidget());
          } else if (snapshot.hasError) {
            _logger.severe(
              "Failed to load _personEntitiesWithThumnailFile",
              snapshot.error,
              snapshot.stackTrace,
            );
            return const Center(child: Icon(Icons.error_outline_rounded));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Text(AppLocalizations.of(context).noResultsFound + '.'),
            );
          } else {
            final results = snapshot.data!;
            final screenWidth = MediaQuery.of(context).size.width;
            final crossAxisCount = (screenWidth / 100).floor();

            final itemSize =
                (screenWidth -
                    ((horizontalEdgePadding * 2) +
                        ((crossAxisCount - 1) * gridPadding))) /
                crossAxisCount;

            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(
                horizontalEdgePadding,
                16,
                horizontalEdgePadding,
                96,
              ),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                mainAxisSpacing: gridPadding,
                crossAxisSpacing: gridPadding,
                crossAxisCount: crossAxisCount,
                childAspectRatio:
                    itemSize / (itemSize + (24 * textScaleFactor)),
              ),
              itemCount: results.length,
              itemBuilder: (context, index) {
                return _RoundedPersonFaceWidget(
                  key: ValueKey(results[index].remoteID),
                  onTap: () async {
                    final dialog = createProgressDialog(
                      context,
                      context.l10n.reassigningLoading,
                    );
                    unawaited(dialog.show());
                    try {
                      await reassignMe(
                        currentPersonID: widget.currentMeId,
                        newPersonID: results[index].remoteID,
                      );
                      if (!context.mounted) return;
                      showToast(
                        context,
                        context.l10n.reassignedToName(
                          name: results[index].data.name,
                        ),
                      );
                      await Future.delayed(const Duration(milliseconds: 1250));
                      unawaited(dialog.hide());
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                    } catch (e) {
                      unawaited(dialog.hide());
                      if (!context.mounted) return;
                      unawaited(
                        showGenericErrorDialog(context: context, error: e),
                      );
                    }
                  },
                  itemSize: itemSize,
                  personEntity: results[index],
                );
              },
            );
          }
        },
      ),
    );
  }

  Future<void> reassignMe({
    required String currentPersonID,
    required String newPersonID,
  }) async {
    try {
      final email = Configuration.instance.getEmail();
      final userID = Configuration.instance.getUserID();

      final updatedPerson1 = await PersonService.instance.updateAttributes(
        currentPersonID,
        email: null,
        userID: null,
      );
      Bus.instance.fire(
        PeopleChangedEvent(
          type: PeopleEventType.saveOrEditPerson,
          source: "reassignMe",
          person: updatedPerson1,
        ),
      );

      final updatedPerson2 = await PersonService.instance.updateAttributes(
        newPersonID,
        email: email,
        userID: userID,
      );
      Bus.instance.fire(
        PeopleChangedEvent(
          type: PeopleEventType.saveOrEditPerson,
          source: "reassignMe",
          person: updatedPerson2,
        ),
      );
    } catch (e) {
      _logger.severe("Failed to reassign me", e);
      rethrow;
    }
  }
}

class _RoundedPersonFaceWidget extends StatelessWidget {
  final FutureVoidCallback onTap;
  final double itemSize;
  final PersonEntity personEntity;

  const _RoundedPersonFaceWidget({
    super.key,
    required this.onTap,
    required this.itemSize,
    required this.personEntity,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              FaceThumbnailSquircleClip(
                child: Container(
                  width: itemSize,
                  height: itemSize,
                  decoration: BoxDecoration(
                    color: getEnteColorScheme(context).strokeFaint,
                  ),
                ),
              ),
              SizedBox(
                width: itemSize,
                height: itemSize,
                child: SizedBox(
                  width: itemSize - 2,
                  height: itemSize - 2,
                  child: FaceThumbnailSquircleClip(
                    child: PersonFaceWidget(
                      personId: personEntity.remoteID,
                      useFullFile: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 0),
            child: Text(
              personEntity.data.name,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: getEnteTextTheme(context).small,
            ),
          ),
        ],
      ),
    );
  }
}

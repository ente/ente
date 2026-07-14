import 'dart:async';
import "dart:math" as math;

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:flutter_animate/flutter_animate.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/services/account/user_service.dart";
import "package:photos/services/machine_learning/face_ml/feedback/cluster_feedback.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/date_input.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/components/action_sheet_widget.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/sharing/album_share_info_widget.dart";
import "package:photos/ui/sharing/user_avator_widget.dart";
import "package:photos/ui/viewer/file/no_thumbnail_widget.dart";
import "package:photos/ui/viewer/gallery/hooks/pick_person_avatar.dart";
import "package:photos/ui/viewer/people/face_thumbnail_squircle.dart";
import "package:photos/ui/viewer/people/link_email_screen.dart";
import "package:photos/ui/viewer/people/merge_clusters_to_person_sheet.dart";
import "package:photos/ui/viewer/people/people_util.dart";
import "package:photos/ui/viewer/people/person_clusters_page.dart";
import "package:photos/ui/viewer/people/person_face_widget.dart";
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/person_contact_linking_util.dart";

class SaveOrEditPerson extends StatefulWidget {
  final String? clusterID;
  final EnteFile? file;
  final bool isEditing;
  final PersonEntity? person;

  const SaveOrEditPerson(
    this.clusterID, {
    super.key,
    this.file,
    this.person,
    this.isEditing = false,
  }) : assert(
         !isEditing || person != null,
         'Person cannot be null when editing',
       );

  @override
  State<SaveOrEditPerson> createState() => _SaveOrEditPersonState();
}

class _SaveOrEditPersonState extends State<SaveOrEditPerson> {
  static const int _maxSuggestedPersons = 3;
  bool isKeypadOpen = false;
  String _inputName = "";
  String? _selectedDate;
  String? _email;
  bool _isPinned = false;
  bool _hideFromMemories = false;
  bool userAlreadyAssigned = false;
  late final Logger _logger = Logger("_SavePersonState");
  Timer? _debounce;
  PersonEntity? person;
  final _nameFocsNode = FocusNode();
  List<PersonEntity> _allPersons = [];

  @override
  void initState() {
    super.initState();
    _inputName = widget.person?.data.name ?? "";
    _selectedDate = widget.person?.data.birthDate;
    _email = widget.person?.data.email;
    person = widget.person;
    _isPinned = widget.person?.data.isPinned ?? false;
    _hideFromMemories = widget.person?.data.hideFromMemories ?? false;
    _nameFocsNode.addListener(_handleNameFocusChange);
    _loadPersons();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nameFocsNode.removeListener(_handleNameFocusChange);
    _nameFocsNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    final colorScheme = getEnteColorScheme(context);
    final suggestions = _shouldShowSuggestions
        ? _getPersonSuggestions()
        : const <PersonEntity>[];
    return PopScope(
      canPop: !(changed && _inputName.isNotEmpty),
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) {
          return;
        }

        _nameFocsNode.unfocus();
        final result = await _saveChangesPrompt(context);

        if (result is PersonEntity) {
          if (context.mounted) {
            Navigator.pop(context, result);
          }

          return;
        }

        late final bool shouldPop;
        if (result == ButtonAction.first || result == ButtonAction.second) {
          shouldPop = true;
        } else {
          shouldPop = false;
        }

        if (context.mounted && shouldPop) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: isKeypadOpen,
        appBar: AppBar(
          title: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              widget.isEditing
                  ? context.l10n.editPerson
                  : context.l10n.savePerson,
            ),
          ),
        ),
        body: GestureDetector(
          onTap: () {
            FocusScope.of(context).unfocus();
          },
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(
                      bottom: 32.0,
                      left: 16.0,
                      right: 16.0,
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 48),
                        if (person != null)
                          Stack(
                            children: [
                              SizedBox(
                                height: 110,
                                width: 110,
                                child: FaceThumbnailSquircleClip(
                                  child: PersonFaceWidget(
                                    key: ValueKey(
                                      person?.data.avatarFaceID ?? "",
                                    ),
                                    personId: person!.remoteID,
                                  ),
                                ),
                              ),
                              if (person != null)
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8.0),
                                      boxShadow: Theme.of(
                                        context,
                                      ).colorScheme.enteTheme.shadowMenu,
                                      color: getEnteColorScheme(
                                        context,
                                      ).backgroundElevated2,
                                    ),
                                    child: IconButton(
                                      icon: const Icon(Icons.edit),
                                      iconSize:
                                          16, // specify the size of the icon
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () async {
                                        final result =
                                            await showPersonAvatarPhotoSheet(
                                              context,
                                              person!,
                                            );
                                        if (result != null) {
                                          _logger.info('Person avatar updated');
                                          setState(() {
                                            person = result;
                                          });
                                          Bus.instance.fire(
                                            PeopleChangedEvent(
                                              type: PeopleEventType
                                                  .saveOrEditPerson,
                                              source: "_SaveOrEditPersonState",
                                              person: result,
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        if (person == null)
                          SizedBox(
                            height: 110,
                            width: 110,
                            child: FaceThumbnailSquircleClip(
                              child: widget.clusterID != null
                                  ? PersonFaceWidget(
                                      clusterID: widget.clusterID,
                                    )
                                  : const NoThumbnailWidget(addBorder: false),
                            ),
                          ),
                        const SizedBox(height: 36),
                        TextFormField(
                          keyboardType: TextInputType.name,
                          textCapitalization: TextCapitalization.words,
                          autocorrect: false,
                          focusNode: _nameFocsNode,
                          onChanged: (value) {
                            if (_debounce?.isActive ?? false) {
                              _debounce?.cancel();
                            }
                            _debounce = Timer(
                              const Duration(milliseconds: 300),
                              () {
                                setState(() {
                                  _inputName = value;
                                });
                              },
                            );
                          },
                          initialValue: _inputName,
                          decoration: InputDecoration(
                            focusedBorder: OutlineInputBorder(
                              borderRadius: const BorderRadius.all(
                                Radius.circular(8.0),
                              ),
                              borderSide: BorderSide(
                                color: getEnteColorScheme(context).strokeMuted,
                              ),
                            ),
                            fillColor: getEnteColorScheme(context).fillFaint,
                            filled: true,
                            hintText: context.l10n.enterName,
                            hintStyle: getEnteTextTheme(context).bodyFaint,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            border: UnderlineInputBorder(
                              borderSide: BorderSide.none,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOutQuad,
                          child: suggestions.isEmpty
                              ? const SizedBox.shrink()
                              : Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: _PersonSuggestionsDropdown(
                                    persons: suggestions,
                                    onPersonTap: _onSuggestionSelected,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 16),
                        DatePickerField(
                          hintText: context.l10n.enterDateOfBirth,
                          firstDate: DateTime(100),
                          lastDate: DateTime.now(),
                          initialValue: _selectedDate,
                          isRequired: false,
                          onChanged: (date) {
                            setState(() {
                              // format date to yyyy-MM-dd
                              _selectedDate = date
                                  ?.toIso8601String()
                                  .split("T")
                                  .first;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOutQuad,
                          child: _EmailSection(_email, person?.remoteID),
                        ),
                        const SizedBox(height: 24),
                        ButtonWidget(
                          buttonType: ButtonType.primary,
                          labelText: context.l10n.save,
                          isDisabled: !changed || _inputName.isEmpty,
                          onTap: () async {
                            if (widget.isEditing) {
                              final updatedPersonEntity = await updatePerson(
                                context,
                              );
                              if (updatedPersonEntity != null) {
                                if (!context.mounted) return;
                                Navigator.pop(context, updatedPersonEntity);
                              }
                            } else {
                              final newPersonEntity =
                                  await addNewPerson(
                                    context,
                                    text: _inputName,
                                    clusterID: widget.clusterID!,
                                    birthdate: _selectedDate,
                                    email: _email,
                                  ).catchError((e) {
                                    _logger.severe(
                                      "Error adding new person",
                                      e,
                                    );
                                    return null;
                                  });
                              if (newPersonEntity != null) {
                                if (!context.mounted) return;
                                Navigator.pop(context, newPersonEntity);
                              }
                            }
                          },
                        ),
                        if (!widget.isEditing) ...[
                          const SizedBox(height: 24),
                          Align(
                            alignment: Alignment.center,
                            child: TextButton(
                              onPressed: _onMergeWithExisting,
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                context.l10n.mergeWithExisting,
                                style: textTheme.small.copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: colorScheme.primary500,
                                  decoration: TextDecoration.underline,
                                  decorationColor: colorScheme.primary500,
                                ),
                              ),
                            ),
                          ),
                        ],
                        if (widget.isEditing) ...[
                          const SizedBox(height: 32),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              context.l10n.mergedPhotos,
                              style: textTheme.body,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: 12.0,
                              top: 24.0,
                            ),
                            child: PersonClustersWidget(person!),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onMergeWithExisting() async {
    final clusterId = widget.clusterID;
    if (clusterId == null || userAlreadyAssigned) {
      return;
    }
    final selection = await showMergeClustersToPersonPage(
      context,
      seedClusterId: clusterId,
    );
    if (!mounted || selection == null || selection.personId.isEmpty) {
      return;
    }
    var selectedPerson = selection.person;
    selectedPerson ??= await PersonService.instance.getPerson(
      selection.personId,
    );
    if (selectedPerson == null) {
      return;
    }
    if (selection.person == null || selection.seedClusterId != clusterId) {
      if (userAlreadyAssigned) {
        return;
      }
      userAlreadyAssigned = true;
      await ClusterFeedbackService.instance.addClusterToExistingPerson(
        person: selectedPerson,
        clusterID: clusterId,
      );
    }
    if (!mounted) {
      return;
    }
    Navigator.pop(context, selectedPerson);
  }

  void _handleNameFocusChange() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadPersons() async {
    final persons = await PersonService.instance.getPersons();
    if (!mounted) {
      return;
    }
    setState(() {
      _allPersons = persons;
    });
  }

  bool get _shouldShowSuggestions =>
      !widget.isEditing &&
      widget.clusterID != null &&
      _nameFocsNode.hasFocus &&
      _inputName.trim().isNotEmpty &&
      !userAlreadyAssigned;

  List<PersonEntity> _getPersonSuggestions() {
    final query = _inputName.trim().toLowerCase();
    if (query.isEmpty || _allPersons.isEmpty) {
      return [];
    }
    final suggestions =
        _allPersons.where((personEntity) {
          final name = personEntity.data.name.trim();
          if (name.isEmpty) {
            return false;
          }
          if (widget.isEditing && personEntity.remoteID == person?.remoteID) {
            return false;
          }
          return name.toLowerCase().contains(query);
        }).toList()..sort(
          (a, b) =>
              a.data.name.toLowerCase().compareTo(b.data.name.toLowerCase()),
        );

    if (suggestions.length > _maxSuggestedPersons) {
      return suggestions.sublist(0, _maxSuggestedPersons);
    }
    return suggestions;
  }

  Future<void> _onSuggestionSelected(PersonEntity selectedPerson) async {
    final clusterId = widget.clusterID;
    if (clusterId == null || userAlreadyAssigned) {
      return;
    }
    FocusScope.of(context).unfocus();
    final shouldMerge = await _showMergeConfirmationSheet(
      context,
      person: selectedPerson,
      clusterId: clusterId,
    );
    if (!mounted || shouldMerge != true) {
      return;
    }
    if (userAlreadyAssigned) {
      return;
    }
    userAlreadyAssigned = true;
    await ClusterFeedbackService.instance.addClusterToExistingPerson(
      person: selectedPerson,
      clusterID: clusterId,
    );
    if (!mounted) {
      return;
    }
    Navigator.pop(context, selectedPerson);
  }

  Future<bool?> _showMergeConfirmationSheet(
    BuildContext context, {
    required PersonEntity person,
    required String clusterId,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _MergePersonConfirmationSheet(person: person, clusterId: clusterId),
    );
  }

  Future<dynamic> _saveChangesPrompt(BuildContext context) async {
    PersonEntity? updatedPersonEntity;
    return await showActionSheet(
      body: context.l10n.saveChangesBeforeLeavingQuestion,
      context: context,
      buttons: [
        ButtonWidget(
          buttonType: ButtonType.neutral,
          labelText: AppLocalizations.of(context).save,
          isInAlert: true,
          buttonAction: ButtonAction.first,
          shouldStickToDarkTheme: true,
          onTap: () async {
            if (widget.isEditing) {
              updatedPersonEntity = await updatePerson(context);
            } else {
              try {
                updatedPersonEntity = await addNewPerson(
                  context,
                  text: _inputName,
                  clusterID: widget.clusterID!,
                  birthdate: _selectedDate,
                  email: _email,
                );
              } catch (e) {
                _logger.severe("Error updating person", e);
              }
            }
          },
        ),
        ButtonWidget(
          buttonType: ButtonType.secondary,
          labelText: context.l10n.dontSave,
          isInAlert: true,
          buttonAction: ButtonAction.second,
          shouldStickToDarkTheme: true,
        ),
        ButtonWidget(
          buttonType: ButtonType.secondary,
          labelText: AppLocalizations.of(context).cancel,
          isInAlert: true,
          buttonAction: ButtonAction.cancel,
          shouldStickToDarkTheme: true,
        ),
      ],
    ).then((buttonResult) {
      if (buttonResult == null ||
          buttonResult.action == null ||
          buttonResult.action == ButtonAction.cancel) {
        return ButtonAction.cancel;
      } else if (buttonResult.action == ButtonAction.second) {
        return ButtonAction.second;
      } else {
        return updatedPersonEntity;
      }
    });
  }

  Future<PersonEntity?> addNewPerson(
    BuildContext context, {
    String text = '',
    required String clusterID,
    String? birthdate,
    String? email,
  }) async {
    if (email != null &&
        email.isNotEmpty &&
        await checkIfEmailAlreadyAssignedToAPerson(email)) {
      _logger.severe(
        "Failed to addNewPerson, email is already assigned to a person",
      );
      if (!context.mounted) return null;
      await showAlreadyLinkedEmailDialog(context, email);
      return null;
    }

    try {
      if (userAlreadyAssigned) {
        return null;
      }
      if (text.trim() == "") {
        return null;
      }
      userAlreadyAssigned = true;
      final personEntity = await PersonService.instance.addPerson(
        name: text,
        clusterID: clusterID,
        isPinned: _isPinned,
        hideFromMemories: _hideFromMemories,
        birthdate: birthdate,
        email: email,
      );
      final bool extraPhotosFound = await ClusterFeedbackService.instance
          .checkAndDoAutomaticMerges(personEntity, personClusterID: clusterID);
      if (extraPhotosFound && context.mounted) {
        showShortToast(context, AppLocalizations.of(context).extraPhotosFound);
      }
      Bus.instance.fire(
        PeopleChangedEvent(
          type: PeopleEventType.saveOrEditPerson,
          source: "_SaveOrEditPersonState addNewPerson",
          person: personEntity,
        ),
      );
      return personEntity;
    } catch (e) {
      _logger.severe("Error adding new person", e);
      userAlreadyAssigned = false;
      if (!context.mounted) return null;
      await showGenericErrorDialog(context: context, error: e);
      return null;
    }
  }

  bool get changed => widget.isEditing
      ? (_inputName.trim() != person!.data.name ||
            _selectedDate != person!.data.birthDate ||
            _email != person!.data.email ||
            _isPinned != person!.data.isPinned ||
            _hideFromMemories != person!.data.hideFromMemories)
      : _inputName.trim().isNotEmpty;

  Future<PersonEntity?> updatePerson(BuildContext context) async {
    try {
      if (_email != null &&
          _email!.isNotEmpty &&
          _email != person!.data.email &&
          await checkIfEmailAlreadyAssignedToAPerson(_email!)) {
        if (!context.mounted) return null;
        await showAlreadyLinkedEmailDialog(context, _email!);
        return null;
      }
      final String name = _inputName.trim();
      final String? birthDate = _selectedDate;
      final personEntity = await PersonService.instance.updateAttributes(
        person!.remoteID,
        name: name,
        birthDate: birthDate,
        isPinned: _isPinned,
        hideFromMemories: _hideFromMemories,
        email: _email,
      );

      Bus.instance.fire(
        PeopleChangedEvent(
          type: PeopleEventType.saveOrEditPerson,
          source: "_SaveOrEditPersonState updatePerson",
          person: personEntity,
        ),
      );
      return personEntity;
    } catch (e) {
      _logger.severe("Error adding updating person", e);
      if (!context.mounted) return null;
      await showGenericErrorDialog(context: context, error: e);
      return null;
    }
  }
}

class _PersonSuggestionsDropdown extends StatelessWidget {
  final List<PersonEntity> persons;
  final ValueChanged<PersonEntity> onPersonTap;

  const _PersonSuggestionsDropdown({
    required this.persons,
    required this.onPersonTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.backgroundElevated2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.strokeMuted.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final person in persons)
            _PersonSuggestionTile(
              key: ValueKey(person.remoteID),
              person: person,
              onTap: () => onPersonTap(person),
            ),
        ],
      ),
    );
  }
}

class _PersonSuggestionTile extends StatelessWidget {
  final PersonEntity person;
  final VoidCallback onTap;

  const _PersonSuggestionTile({
    super.key,
    required this.person,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const double rowHeight = 52;
    const double innerHeight = 44;
    const double avatarSize = 30;
    final textTheme = getEnteTextTheme(context);
    final colorScheme = getEnteColorScheme(context);
    final cachedPixelWidth =
        (avatarSize * MediaQuery.devicePixelRatioOf(context)).round();

    return SizedBox(
      height: rowHeight,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            splashColor: colorScheme.fillFaintPressed,
            highlightColor: colorScheme.fillFaintPressed,
            child: SizedBox(
              height: innerHeight,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Row(
                  children: [
                    SizedBox(
                      width: avatarSize,
                      height: avatarSize,
                      child: FaceThumbnailSquircleClip(
                        child: PersonFaceWidget(
                          key: ValueKey("person_suggestion_${person.remoteID}"),
                          personId: person.remoteID,
                          useFullFile: false,
                          cachedPixelWidth: cachedPixelWidth,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        person.data.name,
                        style: textTheme.mini.copyWith(
                          color: colorScheme.textBase,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MergePersonConfirmationSheet extends StatelessWidget {
  final PersonEntity person;
  final String clusterId;

  const _MergePersonConfirmationSheet({
    required this.person,
    required this.clusterId,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = getEnteTextTheme(context);
    final colorScheme = getEnteColorScheme(context);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.backgroundElevated2,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        border: Border.all(
          color: colorScheme.strokeMuted.withValues(alpha: 0.2),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MergeFacePair(
                    clusterId: clusterId,
                    personId: person.remoteID,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.mergeWithPersonTitle(name: person.data.name),
                    style: textTheme.largeBold.copyWith(
                      fontSize: 20,
                      height: 20 / 20,
                      letterSpacing: -0.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 11),
                  Text(
                    l10n.mergeWithPersonDescription(name: person.data.name),
                    style: textTheme.smallMuted.copyWith(
                      height: 20 / 14,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  _MergeSheetActionButton(
                    label: l10n.merge,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: _MergeSheetCloseButton(
                onTap: () => Navigator.of(context).pop(false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MergeFacePair extends StatelessWidget {
  final String clusterId;
  final String personId;

  const _MergeFacePair({required this.clusterId, required this.personId});

  @override
  Widget build(BuildContext context) {
    const double leftSize = 74;
    const double rightSize = 71;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);

    return SizedBox(
      width: 120,
      height: 90,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Transform.rotate(
              angle: -5 * math.pi / 180,
              child: _MergeFaceThumbnail(
                size: leftSize,
                clusterId: clusterId,
                cachedPixelWidth: (leftSize * devicePixelRatio).round(),
              ),
            ),
          ),
          Positioned(
            left: 35,
            top: 5,
            child: Transform.rotate(
              angle: 12 * math.pi / 180,
              child: _MergeFaceThumbnail(
                size: rightSize,
                personId: personId,
                cachedPixelWidth: (rightSize * devicePixelRatio).round(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MergeFaceThumbnail extends StatelessWidget {
  final double size;
  final String? personId;
  final String? clusterId;
  final int cachedPixelWidth;

  const _MergeFaceThumbnail({
    required this.size,
    required this.cachedPixelWidth,
    this.personId,
    this.clusterId,
  }) : assert(
         personId != null || clusterId != null,
         "Merge face thumbnail requires personId or clusterId",
       );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: FaceThumbnailSquircleClip(
        child: PersonFaceWidget(
          personId: personId,
          clusterID: clusterId,
          useFullFile: false,
          cachedPixelWidth: cachedPixelWidth,
        ),
      ),
    );
  }
}

class _MergeSheetActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _MergeSheetActionButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final borderRadius = BorderRadius.circular(14);

    return SizedBox(
      height: 52,
      width: double.infinity,
      child: Material(
        color: colorScheme.primary500,
        borderRadius: borderRadius,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: textTheme.smallBold.copyWith(
                color: Colors.white,
                height: 20 / 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MergeSheetCloseButton extends StatelessWidget {
  final VoidCallback onTap;

  const _MergeSheetCloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    const double size = 40;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: colorScheme.fillFaint,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.close, size: 20, color: colorScheme.textBase),
      ),
    );
  }
}

class _EmailSection extends StatefulWidget {
  final String? personID;
  final String? email;
  const _EmailSection(this.email, this.personID);

  @override
  State<_EmailSection> createState() => _EmailSectionState();
}

class _EmailSectionState extends State<_EmailSection> {
  String? _email;
  final _logger = Logger("_EmailSectionState");
  bool _initialEmailIsUserEmail = false;
  late final List<User> _contacts;

  @override
  void initState() {
    super.initState();
    _email = widget.email;
    _initialEmailIsUserEmail = Configuration.instance.getEmail() == _email;
    _contacts = _getContacts();
  }

  @override
  void didUpdateWidget(covariant _EmailSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.email != widget.email) {
      setState(() {
        _email = widget.email;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const limitCountTo = 5;
    final avatarSize = getAvatarSize(AvatarType.large);
    final overlapPadding = getOverlapPadding(AvatarType.large);
    if (_email == null || _email!.isEmpty) {
      return AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOutQuad,
        child: Padding(
          padding: const EdgeInsets.only(top: 20),
          child:
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: getEnteColorScheme(context).fillFaint,
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (_contacts.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 1.0),
                          height: 32 + 2 * UserAvatarWidget.strokeWidth,
                          width:
                              ((avatarSize) * (limitCountTo + 1)) -
                              (((avatarSize) - overlapPadding) * limitCountTo) +
                              (2 * UserAvatarWidget.strokeWidth),
                          child: AlbumSharesIcons(
                            sharees: _contacts,
                            limitCountTo: limitCountTo,
                            type: AvatarType.large,
                            padding: EdgeInsets.zero,
                            stackAlignment: Alignment.center,
                          ),
                        ),
                      ),
                    if (_contacts.isNotEmpty) const SizedBox(height: 38),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: FutureBuilder<bool>(
                        future: isMeAssigned(),
                        builder: (context, snapshot) {
                          if (snapshot.hasData) {
                            final isMeAssigned = snapshot.data!;
                            if (!isMeAssigned || _initialEmailIsUserEmail) {
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: ButtonWidget(
                                      buttonType: ButtonType.secondary,
                                      labelText:
                                          context.l10n.thisIsMeExclamation,
                                      onTap: () async {
                                        _updateEmailField(
                                          Configuration.instance.getEmail(),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ButtonWidget(
                                      buttonType: ButtonType.primary,
                                      labelText: context.l10n.linkEmail,
                                      shouldSurfaceExecutionStates: false,
                                      onTap: () async {
                                        final newEmail = await routeToPage(
                                          context,
                                          LinkEmailScreen(
                                            widget.personID,
                                            isFromSaveOrEditPerson: true,
                                          ),
                                        );
                                        if (newEmail != null) {
                                          _updateEmailField(newEmail as String);
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              );
                            } else {
                              return ButtonWidget(
                                buttonType: ButtonType.primary,
                                labelText: context.l10n.linkEmail,
                                shouldSurfaceExecutionStates: false,
                                onTap: () async {
                                  final newEmail = await routeToPage(
                                    context,
                                    LinkEmailScreen(
                                      widget.personID,
                                      isFromSaveOrEditPerson: true,
                                    ),
                                  );
                                  if (newEmail != null) {
                                    _updateEmailField(newEmail as String);
                                  }
                                },
                              );
                            }
                          } else if (snapshot.hasError) {
                            _logger.severe(
                              "Error getting isMeAssigned",
                              snapshot.error,
                            );
                            return const EnteLoadingWidget();
                          } else {
                            return const EnteLoadingWidget();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOutQuad,
              ),
        ),
      );
    } else {
      return TextFormField(
        canRequestFocus: false,
        autocorrect: false,
        decoration: InputDecoration(
          suffixIcon: GestureDetector(
            onTap: () {
              _updateEmailField("");
            },
            child: Icon(
              Icons.close_outlined,
              color: getEnteColorScheme(context).strokeMuted,
            ),
          ),
          fillColor: getEnteColorScheme(context).fillFaint,
          filled: true,
          hintText: _email,
          hintStyle: getEnteTextTheme(context).bodyFaint,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: UnderlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ).animate().fadeIn(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOutQuad,
      );
    }
  }

  void _updateEmailField(String? newEmail) {
    final saveOrEditPersonState = context
        .findAncestorStateOfType<_SaveOrEditPersonState>()!;
    saveOrEditPersonState.setState(() {
      saveOrEditPersonState._email = newEmail;
    });
  }

  List<User> _getContacts() {
    final userEmailsToAviod =
        PersonService.instance.emailToPartialPersonDataMapCache.keys;
    final ownerEmail = Configuration.instance.getEmail();
    final relevantUsers = UserService.instance.getRelevantContacts()
      ..add(User(email: ownerEmail!))
      ..removeWhere((user) => userEmailsToAviod.contains(user.email));

    relevantUsers.sort((a, b) => (a.email).compareTo(b.email));

    return relevantUsers;
  }
}

import "dart:math" as math;

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/services/machine_learning/face_ml/feedback/cluster_feedback.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/date_input.dart";
import "package:photos/ui/components/action_sheet_widget.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/file/no_thumbnail_widget.dart";
import "package:photos/ui/viewer/gallery/hooks/pick_person_avatar.dart";
import "package:photos/ui/viewer/people/face_thumbnail_squircle.dart";
import "package:photos/ui/viewer/people/merge_clusters_to_person_sheet.dart";
import "package:photos/ui/viewer/people/person_clusters_page.dart";
import "package:photos/ui/viewer/people/person_face_widget.dart";
import "package:photos/utils/contact_string_util.dart";
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
  String _inputName = "";
  String? _selectedDate;
  bool _isBirthdayValid = true;
  String? _email;
  bool _isMe = false;
  bool _isMeAssignedToAnotherPerson = true;
  bool _isPinned = false;
  bool _hideFromMemories = false;
  bool userAlreadyAssigned = false;
  late final Logger _logger = Logger("_SavePersonState");
  PersonEntity? person;
  String? _mergeSuggestionPersonId;
  final _nameFocsNode = FocusNode();
  List<PersonEntity> _allPersons = [];
  List<GenericSearchResult> _mergeablePersons = [];

  String? get _emailToSave => trimToNull(_email);

  int? get _currentUserIDToSave =>
      currentUserIDForContactLinkEmail(_emailToSave);

  bool get _initiallyIsMe => isCurrentUserContactLink(
    email: widget.person?.data.email,
    userID: widget.person?.data.userID,
  );

  bool get _isMeChanged => widget.isEditing && _isMe != _initiallyIsMe;

  bool get _contactLinkEmailChanged =>
      widget.isEditing && _emailToSave != trimToNull(person?.data.email);

  bool get _shouldClearContactUserID =>
      person?.data.userID != null &&
      ((_isMeChanged && !_isMe) ||
          (_contactLinkEmailChanged && _currentUserIDToSave == null));

  bool get _shouldSetCurrentUserID =>
      widget.isEditing &&
      _currentUserIDToSave != null &&
      person?.data.userID != _currentUserIDToSave;

  bool get _shouldUpdateContactUserID =>
      _shouldClearContactUserID || _shouldSetCurrentUserID;

  @override
  void initState() {
    super.initState();
    _inputName = widget.person?.data.name ?? "";
    _selectedDate = widget.person?.data.birthDate;
    _email = widget.person?.data.email;
    person = widget.person;
    _isMe = _initiallyIsMe;
    _isPinned = widget.person?.data.isPinned ?? false;
    _hideFromMemories = widget.person?.data.hideFromMemories ?? false;
    _nameFocsNode.addListener(_handleNameFocusChange);
    _loadPersons();
  }

  @override
  void dispose() {
    _nameFocsNode.removeListener(_handleNameFocusChange);
    _nameFocsNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
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
        backgroundColor: colors.backgroundBase,
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
            children: [
              Expanded(
                child: AppBarComponent(
                  title: widget.isEditing
                      ? context.l10n.editPerson
                      : context.l10n.savePerson,
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(child: _buildAvatar()),
                            const SizedBox(height: Spacing.xxl),
                            if (_mergeablePersons.isNotEmpty) ...[
                              _MergeWithExistingSection(
                                clusterId: widget.clusterID!,
                                suggestedPersonId: _mergeSuggestionPersonId,
                                onTap: _onMergeWithExisting,
                              ),
                              const SizedBox(height: Spacing.xxl),
                            ],
                            TextInputComponent(
                              label: context.l10n.name,
                              hintText: context.l10n.enterName,
                              initialValue: widget.person?.data.name,
                              focusNode: _nameFocsNode,
                              keyboardType: TextInputType.name,
                              textCapitalization: TextCapitalization.words,
                              autocorrect: false,
                              isRequired: true,
                              onChanged: (value) =>
                                  setState(() => _inputName = value),
                            ),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOutQuad,
                              child: suggestions.isEmpty
                                  ? const SizedBox.shrink()
                                  : Padding(
                                      padding: const EdgeInsets.only(
                                        top: Spacing.sm,
                                      ),
                                      child: _PersonSuggestionsDropdown(
                                        persons: suggestions,
                                        onPersonTap: _onSuggestionSelected,
                                      ),
                                    ),
                            ),
                            if (_showThisIsMe) ...[
                              const SizedBox(height: Spacing.sm),
                              LabeledControlComponent(
                                control: CheckboxComponent(
                                  selected: _isMe,
                                  onChanged: _setIsMe,
                                ),
                                label: context.l10n.thisIsMeExclamation,
                                foreground: colors.textLighter,
                                onTap: () => _setIsMe(!_isMe),
                              ),
                            ],
                            const SizedBox(height: Spacing.xxl),
                            _buildBirthdayInput(),
                            if (widget.isEditing) ...[
                              const SizedBox(height: 28),
                              Text(
                                context.l10n.mergedPhotos,
                                style: TextStyles.h2.copyWith(
                                  color: colors.textBase,
                                ),
                              ),
                              const SizedBox(height: Spacing.md),
                              PersonClustersWidget(person!),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.all(Spacing.xxl),
                child: Column(
                  children: [
                    ButtonComponent(
                      label: context.l10n.savePerson,
                      isDisabled: !_canSave,
                      shouldShowSuccessState: false,
                      onTap: _canSave ? _savePerson : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _showThisIsMe =>
      Configuration.instance.getEmail() != null &&
      (_isMe || !_isMeAssignedToAnotherPerson);

  Widget _buildAvatar() {
    const size = 108.0;
    final avatar = SizedBox(
      width: size,
      height: size,
      child: FaceThumbnailSquircleClip(
        borderRadius: faceThumbnailSquircleBorderRadius(size),
        child: person != null
            ? PersonFaceWidget(
                key: ValueKey(person!.data.avatarFaceID ?? ""),
                personId: person!.remoteID,
              )
            : widget.clusterID != null
            ? PersonFaceWidget(clusterID: widget.clusterID)
            : const NoThumbnailWidget(addBorder: false),
      ),
    );
    if (person == null) {
      return avatar;
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: 0,
          bottom: 0,
          child: _AvatarEditButton(onTap: _editAvatar),
        ),
      ],
    );
  }

  Widget _buildBirthdayInput() {
    return DatePickerField(
      label: context.l10n.birthday,
      hintText: context.l10n.enterDateOfBirthHint,
      firstDate: DateTime(100),
      lastDate: DateTime.now(),
      initialValue: _selectedDate,
      isRequired: false,
      onValidityChanged: (isValid) =>
          setState(() => _isBirthdayValid = isValid),
      onChanged: (date) => setState(
        () => _selectedDate = date?.toIso8601String().split("T").first,
      ),
    );
  }

  Future<void> _editAvatar() async {
    final result = await showPersonAvatarPhotoSheet(context, person!);
    if (!mounted || result == null) {
      return;
    }
    _logger.info('Person avatar updated');
    setState(() => person = result);
    Bus.instance.fire(
      PeopleChangedEvent(
        type: PeopleEventType.saveOrEditPerson,
        source: "_SaveOrEditPersonState",
        person: result,
      ),
    );
  }

  void _setIsMe(bool selected) {
    setState(() {
      _isMe = selected;
      _email = selected
          ? Configuration.instance.getEmail()
          : _initiallyIsMe
          ? null
          : widget.person?.data.email;
    });
  }

  Future<void> _savePerson() async {
    if (widget.isEditing) {
      final updatedPersonEntity = await updatePerson(context);
      if (updatedPersonEntity != null && mounted) {
        Navigator.pop(context, updatedPersonEntity);
      }
      return;
    }
    final newPersonEntity = await addNewPerson(
      context,
      text: _inputName,
      clusterID: widget.clusterID!,
      birthdate: _selectedDate,
      email: _email,
    );
    if (newPersonEntity != null && mounted) {
      Navigator.pop(context, newPersonEntity);
    }
  }

  Future<void> _onMergeWithExisting() async {
    final clusterId = widget.clusterID;
    if (clusterId == null || userAlreadyAssigned) {
      return;
    }
    final selection = await showMergeClustersToPersonPage(
      context,
      initialPersons: _mergeablePersons,
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
      _isMeAssignedToAnotherPerson = persons.any(
        (candidate) =>
            candidate.remoteID != person?.remoteID &&
            isCurrentUserContactLink(
              email: candidate.data.email,
              userID: candidate.data.userID,
            ),
      );
    });
    if (!widget.isEditing) {
      final mergeablePersons = await loadMergeablePersons();
      if (!mounted) {
        return;
      }
      setState(() => _mergeablePersons = mergeablePersons);
      if (mergeablePersons.isNotEmpty) {
        await _loadMergeSuggestion();
      }
    }
  }

  Future<void> _loadMergeSuggestion() async {
    final clusterId = widget.clusterID;
    if (clusterId == null) {
      return;
    }
    try {
      final suggestions = await ClusterFeedbackService.instance
          .getAllLargePersonSuggestions();
      for (final suggestion in suggestions) {
        if (suggestion.clusterIDToMerge == clusterId) {
          if (mounted) {
            setState(
              () => _mergeSuggestionPersonId = suggestion.person.remoteID,
            );
          }
          return;
        }
      }
    } catch (error, stackTrace) {
      _logger.warning("Failed to load merge suggestion", error, stackTrace);
    }
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
    return showBottomSheetComponent<bool>(
      context: context,
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
    if (email != null && email.isNotEmpty) {
      final linkedPerson = await findPersonLinkedToEmail(email);
      if (linkedPerson != null) {
        _logger.severe(
          "Failed to addNewPerson, email is already assigned to a person",
        );
        if (!context.mounted) return null;
        await showAlreadyLinkedEmailDialog(
          context,
          email,
          linkedPerson: linkedPerson,
        );
        return null;
      }
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
        userID: currentUserIDForContactLinkEmail(email),
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
            _emailToSave != trimToNull(person!.data.email) ||
            _isMeChanged ||
            _isPinned != person!.data.isPinned ||
            _hideFromMemories != person!.data.hideFromMemories)
      : _inputName.trim().isNotEmpty;

  bool get _canSave =>
      changed && _inputName.trim().isNotEmpty && _isBirthdayValid;

  Future<PersonEntity?> updatePerson(BuildContext context) async {
    try {
      final emailToSave = _emailToSave;
      if (emailToSave != null &&
          emailToSave != trimToNull(person!.data.email)) {
        final linkedPerson = await findPersonLinkedToEmail(
          emailToSave,
          excludedPersonId: person!.remoteID,
        );
        if (linkedPerson != null) {
          if (!context.mounted) return null;
          await showAlreadyLinkedEmailDialog(
            context,
            emailToSave,
            linkedPerson: linkedPerson,
          );
          return null;
        }
      }
      final String name = _inputName.trim();
      final String? birthDate = _selectedDate;
      final userIDToSave = _shouldClearContactUserID
          ? null
          : _currentUserIDToSave;
      final personEntity = _shouldUpdateContactUserID
          ? await PersonService.instance.updateAttributes(
              person!.remoteID,
              name: name,
              birthDate: birthDate,
              isPinned: _isPinned,
              hideFromMemories: _hideFromMemories,
              email: emailToSave,
              userID: userIDToSave,
            )
          : await PersonService.instance.updateAttributes(
              person!.remoteID,
              name: name,
              birthDate: birthDate,
              isPinned: _isPinned,
              hideFromMemories: _hideFromMemories,
              email: emailToSave,
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

class _AvatarEditButton extends StatelessWidget {
  const _AvatarEditButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: context.componentColors.fillLight,
          borderRadius: BorderRadius.circular(Radii.md),
          boxShadow: Theme.of(context).colorScheme.enteTheme.shadowMenu,
        ),
        alignment: Alignment.center,
        child: HugeIcon(
          icon: HugeIcons.strokeRoundedEdit03,
          color: context.componentColors.iconColor,
          size: IconSizes.small,
          strokeWidth: 2,
        ),
      ),
    );
  }
}

class _MergeWithExistingSection extends StatelessWidget {
  const _MergeWithExistingSection({
    required this.clusterId,
    required this.suggestedPersonId,
    required this.onTap,
  });

  final String clusterId;
  final String? suggestedPersonId;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.md,
        Spacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.fillLight,
        borderRadius: BorderRadius.circular(Radii.button),
      ),
      child: Column(
        children: [
          _MergeWithExistingGraphic(
            clusterId: clusterId,
            suggestedPersonId: suggestedPersonId,
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            context.l10n.mergeWithExisting,
            style: TextStyles.body.copyWith(color: colors.textBase),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Spacing.lg),
          ButtonComponent(
            label: context.l10n.selectPerson,
            variant: ButtonComponentVariant.secondary,
            shouldSurfaceExecutionStates: false,
            shouldShowSuccessState: false,
            onTap: onTap,
          ),
        ],
      ),
    );
  }
}

class _MergeWithExistingGraphic extends StatelessWidget {
  const _MergeWithExistingGraphic({
    required this.clusterId,
    required this.suggestedPersonId,
  });

  final String clusterId;
  final String? suggestedPersonId;

  @override
  Widget build(BuildContext context) {
    const thumbnailSize = 48.0;
    final colors = context.componentColors;
    final cachedPixelWidth =
        (thumbnailSize * MediaQuery.devicePixelRatioOf(context)).round();

    return SizedBox(
      width: 110,
      height: 54,
      child: Stack(
        children: [
          Positioned(
            left: 3,
            top: 3,
            child: Transform.rotate(
              angle: -7 * math.pi / 180,
              child: _MergeFaceThumbnail(
                size: thumbnailSize,
                clusterId: clusterId,
                cachedPixelWidth: cachedPixelWidth,
              ),
            ),
          ),
          Positioned(
            right: 3,
            top: 3,
            child: Transform.rotate(
              angle: 7 * math.pi / 180,
              child: suggestedPersonId != null
                  ? _MergeFaceThumbnail(
                      size: thumbnailSize,
                      personId: suggestedPersonId,
                      cachedPixelWidth: cachedPixelWidth,
                    )
                  : Container(
                      width: thumbnailSize,
                      height: thumbnailSize,
                      decoration: BoxDecoration(
                        color: colors.backgroundBase,
                        borderRadius: faceThumbnailSquircleBorderRadius(
                          thumbnailSize,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedUser,
                        color: colors.textLight,
                        size: IconSizes.small,
                        strokeWidth: 1.5,
                      ),
                    ),
            ),
          ),
          Positioned(
            left: 44,
            top: 15,
            child: Container(
              padding: const EdgeInsets.all(Spacing.xs),
              decoration: BoxDecoration(
                color: colors.green,
                shape: BoxShape.circle,
                border: Border.all(color: colors.fillLight),
              ),
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedArrowLeftRight,
                color: colors.specialWhite,
                size: 12,
                strokeWidth: 2,
              ),
            ),
          ),
        ],
      ),
    );
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

    return BottomSheetComponent(
      closeResult: false,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MergeFacePair(clusterId: clusterId, personId: person.remoteID),
          const SizedBox(height: Spacing.xl),
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
        ],
      ),
      actions: [
        ButtonComponent(
          label: l10n.merge,
          shouldSurfaceExecutionStates: false,
          onTap: () => Navigator.of(context).pop(true),
        ),
      ],
      crossAxisAlignment: CrossAxisAlignment.stretch,
      padding: const EdgeInsets.fromLTRB(
        Spacing.xl,
        Spacing.lg,
        Spacing.xl,
        Spacing.xl,
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

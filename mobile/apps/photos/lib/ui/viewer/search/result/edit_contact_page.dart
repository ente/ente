import "dart:async";
import "dart:typed_data";

import "package:ente_components/ente_components.dart";
import "package:ente_contacts/contacts.dart" as contacts;
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/module/download/thumbnail.dart";
import "package:photos/services/machine_learning/face_ml/face_filtering/face_filtering_constants.dart";
import "package:photos/services/machine_learning/face_ml/feedback/cluster_feedback.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/photos_contacts_service.dart";
import "package:photos/services/search_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/components/action_sheet_widget.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/people/face_thumbnail_squircle.dart";
import "package:photos/ui/viewer/search/result/contact_person_picker_page.dart";
import "package:photos/ui/viewer/search/result/contact_photo_adjust_page.dart";
import "package:photos/ui/viewer/search/result/contact_photo_picker_sheet.dart";
import "package:photos/utils/avatar_util.dart";
import "package:photos/utils/contact_photo_util.dart";
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/person_contact_linking_util.dart";

class EditContactPage extends StatefulWidget {
  final int contactUserId;
  final String email;
  final contacts.ContactRecord? existingContact;

  const EditContactPage({
    required this.contactUserId,
    required this.email,
    required this.existingContact,
    super.key,
  });

  @override
  State<EditContactPage> createState() => _EditContactPageState();
}

class _EditContactPageState extends State<EditContactPage> {
  static const _avatarSize = 108.0;
  static const _editBadgeSize = 32.0;

  final _logger = Logger("EditContactPage");
  late final TextEditingController _nameController;
  late final FocusNode _nameFocusNode;
  bool _isSaving = false;
  bool _isLoadingPhoto = false;
  bool _photoDirty = false;
  Uint8List? _draftPhotoBytes;
  int _photoLoadGeneration = 0;
  PersonEntity? _initialLinkedPerson;
  PersonEntity? _draftLinkedPerson;
  String? _draftUnassignedClusterID;
  bool _linkDirty = false;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.existingContact?.data?.name ?? "")
          ..addListener(() {
            if (mounted) {
              setState(() {});
            }
          });
    _nameFocusNode = FocusNode();
    _loadExistingPhoto();
    _loadLinkedPersonDraft();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  bool get _canSave => !_isSaving && _nameController.text.trim().isNotEmpty;
  String get _initialName => (widget.existingContact?.data?.name ?? "").trim();
  bool get _hasUnsavedChanges =>
      _nameController.text.trim() != _initialName || _photoDirty || _linkDirty;
  bool get _hasLinkedPersonDraft =>
      _draftLinkedPerson != null || _draftUnassignedClusterID != null;
  bool get _hasContactPhoto =>
      _draftPhotoBytes != null ||
      (!_photoDirty &&
          widget.existingContact?.profilePictureAttachmentId != null);

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final l10n = AppLocalizations.of(context);

    return PopScope(
      canPop: !_isSaving && !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _isSaving || !_hasUnsavedChanges) {
          return;
        }

        final action = await _showExitConfirmationDialog(context);
        if (!mounted || action == null || action == ButtonAction.cancel) {
          return;
        }

        if (_canSave && action == ButtonAction.first) {
          await _saveContact();
          return;
        }

        final shouldPop = _canSave
            ? action == ButtonAction.second
            : action == ButtonAction.first;
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: colors.backgroundBase,
        body: Column(
          children: [
            Expanded(
              child: NotificationListener<ScrollStartNotification>(
                onNotification: (notification) {
                  if (notification.dragDetails != null &&
                      _nameFocusNode.hasFocus) {
                    _nameFocusNode.unfocus();
                  }
                  return false;
                },
                child: AppBarComponent(
                  title: l10n.editContact,
                  onBack: () {
                    Navigator.of(context).maybePop();
                  },
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: SizedBox(
                                width: _avatarSize,
                                height: _avatarSize,
                                child: GestureDetector(
                                  onTap: _openAvatarEditor,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      _buildAvatar(context, size: _avatarSize),
                                      Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child: _AvatarActionButton(
                                          size: _editBadgeSize,
                                          isUnlink: _hasLinkedPersonDraft,
                                          onTap: _hasLinkedPersonDraft
                                              ? _draftUnlinkPerson
                                              : _openAvatarEditor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextInputComponent(
                              label: l10n.email,
                              initialValue: widget.email,
                              isDisabled: true,
                            ),
                            const SizedBox(height: 20),
                            TextInputComponent(
                              label: l10n.name,
                              hintText: l10n.enterName,
                              controller: _nameController,
                              focusNode: _nameFocusNode,
                              isRequired: true,
                              textCapitalization: TextCapitalization.words,
                              onSubmit: _canSave ? (_) => _saveContact() : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: ButtonComponent(
                label: l10n.saveContact,
                isDisabled: !_canSave,
                shouldShowSuccessState: false,
                onTap: _canSave ? _saveContact : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, {required double size}) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final trimmedName = _nameController.text.trim();
    final identity = AvatarIdentity.account(
      label: trimmedName.isNotEmpty ? trimmedName : widget.email,
      email: widget.email,
      userID: widget.contactUserId,
      currentUserEmail: Configuration.instance.getEmail(),
    );

    if (_isLoadingPhoto) {
      return _ContactThumbnailShell(
        size: size,
        backgroundColor: colorScheme.fillFaint,
        child: const Center(child: EnteLoadingWidget()),
      );
    }

    if (_draftPhotoBytes != null) {
      return _ContactThumbnailShell(
        size: size,
        child: Image.memory(_draftPhotoBytes!, fit: BoxFit.cover),
      );
    }

    return _ContactThumbnailShell(
      size: size,
      backgroundColor: avatarBackgroundColor(context, identity),
      child: Center(
        child: Text(
          identity.initial,
          style: textTheme.h1Bold.copyWith(
            fontSize: 38.25,
            height: 47.813 / 38.25,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Future<void> _loadExistingPhoto() async {
    final existing = widget.existingContact;
    if (existing?.profilePictureAttachmentId == null) {
      return;
    }
    final loadGeneration = ++_photoLoadGeneration;
    setState(() {
      _isLoadingPhoto = true;
    });
    final bytes = await PhotosContactsService.instance
        .getProfilePictureBytesByUserId(widget.contactUserId);
    if (!mounted || loadGeneration != _photoLoadGeneration) {
      return;
    }
    if (_photoDirty || _draftPhotoBytes != null) {
      setState(() {
        _isLoadingPhoto = false;
      });
      return;
    }
    setState(() {
      _draftPhotoBytes = bytes;
      _isLoadingPhoto = false;
      _photoDirty = false;
    });
  }

  Future<void> _loadLinkedPersonDraft() async {
    try {
      final linkedPerson = await findPersonLinkedToContact(
        contactUserId: widget.contactUserId,
        email: widget.email,
      );
      if (!mounted || linkedPerson == null) {
        return;
      }

      final shouldPrefillFromPerson = widget.existingContact == null;
      if (shouldPrefillFromPerson && _nameController.text.trim().isEmpty) {
        _nameController.text = linkedPerson.data.name;
      }
      setState(() {
        _initialLinkedPerson = linkedPerson;
        _draftLinkedPerson = linkedPerson;
      });

      if (shouldPrefillFromPerson && !_photoDirty && _draftPhotoBytes == null) {
        await _loadPersonPhotoDraft(linkedPerson, showError: false);
      }
    } catch (e, s) {
      _logger.warning("Failed to load linked person for contact", e, s);
    }
  }

  Future<void> _openAvatarEditor() async {
    if (_isSaving) {
      return;
    }
    List<ContactPersonPickerCandidate> candidates;
    try {
      final faceResults = await SearchService.instance.getAllFace(
        null,
        minClusterSize: kMinimumClusterSizeAllFaces,
      );
      candidates = buildContactPersonPickerCandidates(
        faceResultParams: faceResults.map((result) => result.params),
        persons: await PersonService.instance.getPersons(),
      );
    } catch (e, s) {
      _logger.warning(
        "Failed to load people before editing contact photo",
        e,
        s,
      );
      await _pickContactPhoto();
      return;
    }
    if (!mounted) {
      return;
    }
    if (candidates.isEmpty) {
      await _pickContactPhoto();
      return;
    }

    final result = await routeToPage(
      context,
      ContactPersonPickerPage(
        contactUserId: widget.contactUserId,
        contactEmail: widget.email,
        candidates: candidates,
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    if (result is ContactPersonPickerPickPhoto) {
      await _pickContactPhoto();
      return;
    }
    if (result is ContactPersonPickerSelected) {
      switch (result.candidate) {
        case ContactPersonPickerPersonCandidate(:final person):
          await _draftSelectedPerson(person);
        case ContactPersonPickerClusterCandidate(:final clusterID):
          await _draftSelectedCluster(clusterID);
      }
    }
  }

  void _draftUnlinkPerson() {
    setState(() {
      _draftLinkedPerson = null;
      _draftUnassignedClusterID = null;
      _linkDirty = _initialLinkedPerson != null;
    });
  }

  bool _personNeedsContactLinkUpdate(PersonEntity person) {
    return person.data.userID != widget.contactUserId ||
        !contactLinkEmailMatches(person.data.email, widget.email);
  }

  Future<void> _draftSelectedPerson(PersonEntity person) async {
    await _loadPersonPhotoDraft(person, showError: true);
    if (!mounted) {
      return;
    }
    _nameController.text = person.data.name;
    setState(() {
      _draftLinkedPerson = person;
      _draftUnassignedClusterID = null;
      _linkDirty =
          _initialLinkedPerson?.remoteID != person.remoteID ||
          _personNeedsContactLinkUpdate(person);
    });
  }

  Future<void> _draftSelectedCluster(String clusterID) async {
    setState(() {
      _draftLinkedPerson = null;
      _draftUnassignedClusterID = clusterID;
      _linkDirty = true;
    });
    await _loadClusterPhotoDraft(clusterID, showError: true);
  }

  Future<void> _loadPersonPhotoDraft(
    PersonEntity person, {
    required bool showError,
  }) => _loadFacePhotoDraft(
    () => buildContactPhotoAttachmentBytesFromPerson(person),
    showError: showError,
  );

  Future<void> _loadClusterPhotoDraft(
    String clusterID, {
    required bool showError,
  }) => _loadFacePhotoDraft(
    () => buildContactPhotoAttachmentBytesFromCluster(clusterID),
    showError: showError,
  );

  Future<void> _loadFacePhotoDraft(
    Future<Uint8List?> Function() loadPhotoBytes, {
    required bool showError,
  }) async {
    final loadGeneration = ++_photoLoadGeneration;
    setState(() {
      _isLoadingPhoto = true;
    });
    Uint8List? photoBytes;
    try {
      photoBytes = await loadPhotoBytes();
    } catch (e, s) {
      _logger.warning("Failed to build contact photo from face", e, s);
    }
    if (!mounted || loadGeneration != _photoLoadGeneration) {
      return;
    }
    if (photoBytes == null) {
      setState(() {
        _isLoadingPhoto = false;
      });
      if (showError) {
        showShortToast(
          context,
          AppLocalizations.of(context).couldNotLoadSelectedPhoto,
        );
      }
      return;
    }
    setState(() {
      _draftPhotoBytes = photoBytes;
      _isLoadingPhoto = false;
      _photoDirty = true;
    });
  }

  Future<void> _pickContactPhoto() async {
    final result = await showContactPhotoPickerSheet(
      context,
      canRemovePhoto: _hasContactPhoto,
    );
    if (result == null) {
      return;
    }
    if (result is ContactPhotoPickerRemove) {
      _photoLoadGeneration++;
      setState(() {
        _draftPhotoBytes = null;
        _isLoadingPhoto = false;
        _photoDirty = true;
      });
      return;
    }
    final selectedFile = (result as ContactPhotoPickerFile).file;
    setState(() {
      _isLoadingPhoto = true;
    });
    final sourceBytes = await getThumbnail(selectedFile);
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoadingPhoto = false;
    });
    if (sourceBytes == null) {
      showShortToast(
        context,
        AppLocalizations.of(context).couldNotLoadSelectedPhoto,
      );
      return;
    }
    final croppedBytes = await routeToPage(
      context,
      ContactPhotoAdjustPage(imageBytes: sourceBytes),
    );
    if (croppedBytes is! Uint8List) {
      return;
    }
    _photoLoadGeneration++;
    setState(() {
      _isLoadingPhoto = true;
    });
    final photoBytes = await compressThumbnailToSizeLimit(croppedBytes);
    if (!mounted) {
      return;
    }
    setState(() {
      _draftPhotoBytes = photoBytes;
      _isLoadingPhoto = false;
      _photoDirty = true;
    });
  }

  Future<void> _createPersonForDraftCluster(String contactName) async {
    final clusterID = _draftUnassignedClusterID;
    if (clusterID == null) {
      return;
    }

    final person = await PersonService.instance.addPerson(
      name: contactName,
      clusterID: clusterID,
    );
    unawaited(
      ClusterFeedbackService.instance
          .checkAndDoAutomaticMerges(person, personClusterID: clusterID)
          .catchError((Object error, StackTrace stackTrace) {
            _logger.warning(
              "Failed to automatically merge clusters for new person",
              error,
              stackTrace,
            );
            return false;
          }),
    );
    _draftLinkedPerson = person;
    _draftUnassignedClusterID = null;
    Bus.instance.fire(
      PeopleChangedEvent(
        type: PeopleEventType.saveOrEditPerson,
        person: person,
        source: "edit_contact_create_person",
      ),
    );
  }

  Future<void> _saveContact() async {
    if (!_canSave) {
      return;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      final contactName = _nameController.text.trim();
      final contactNameChanged = contactName != _initialName;
      await _createPersonForDraftCluster(contactName);
      var saved = await PhotosContactsService.instance.createOrUpdateContact(
        contactUserId: widget.contactUserId,
        name: contactName,
      );
      if (_photoDirty) {
        final draftPhotoBytes = _draftPhotoBytes;
        if (draftPhotoBytes != null) {
          saved = await PhotosContactsService.instance.setProfilePicture(
            contactId: saved.id,
            bytes: draftPhotoBytes,
          );
        } else if (widget.existingContact?.profilePictureAttachmentId != null) {
          saved = await PhotosContactsService.instance.deleteProfilePicture(
            contactId: saved.id,
          );
        }
      }
      await _savePersonLinkChanges(
        contactName: contactName,
        contactNameChanged: contactNameChanged,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(saved);
    } catch (e, s) {
      _logger.severe("Failed to save contact", e, s);
      if (!mounted) {
        return;
      }
      await showGenericErrorDialog(context: context, error: e);
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _savePersonLinkChanges({
    required String contactName,
    required bool contactNameChanged,
  }) async {
    final previousPerson = _initialLinkedPerson;
    final selectedPerson = _draftLinkedPerson;
    final updatedPersons = <PersonEntity>[];

    if (previousPerson != null &&
        (selectedPerson == null ||
            selectedPerson.remoteID != previousPerson.remoteID)) {
      updatedPersons.add(
        await PersonService.instance.updateAttributes(
          previousPerson.remoteID,
          userID: null,
          email: null,
          syncLinkedContactName: false,
        ),
      );
    }

    if (selectedPerson != null) {
      final shouldUpdateSelectedLink =
          previousPerson?.remoteID != selectedPerson.remoteID ||
          _personNeedsContactLinkUpdate(selectedPerson);
      final shouldUpdateSelectedName =
          contactNameChanged && selectedPerson.data.name.trim() != contactName;
      if (shouldUpdateSelectedLink || shouldUpdateSelectedName) {
        updatedPersons.add(
          await PersonService.instance.updateAttributes(
            selectedPerson.remoteID,
            name: shouldUpdateSelectedName ? contactName : null,
            userID: widget.contactUserId,
            email: widget.email,
            syncLinkedContactName: false,
          ),
        );
      }
    }

    for (final updatedPerson in updatedPersons) {
      Bus.instance.fire(
        PeopleChangedEvent(
          type: PeopleEventType.saveOrEditPerson,
          person: updatedPerson,
          source: "edit_contact_link",
        ),
      );
    }
  }

  Future<ButtonAction?> _showExitConfirmationDialog(
    BuildContext context,
  ) async {
    final l10n = AppLocalizations.of(context);
    if (_canSave) {
      final actionResult = await showActionSheet(
        context: context,
        body: l10n.saveChangesBeforeLeavingQuestion,
        buttons: [
          ButtonWidget(
            buttonType: ButtonType.neutral,
            labelText: l10n.save,
            isInAlert: true,
            buttonAction: ButtonAction.first,
            shouldStickToDarkTheme: true,
          ),
          ButtonWidget(
            buttonType: ButtonType.secondary,
            labelText: l10n.dontSave,
            isInAlert: true,
            buttonAction: ButtonAction.second,
            shouldStickToDarkTheme: true,
          ),
          ButtonWidget(
            buttonType: ButtonType.secondary,
            labelText: l10n.cancel,
            isInAlert: true,
            buttonAction: ButtonAction.cancel,
            shouldStickToDarkTheme: true,
          ),
        ],
      );
      return actionResult?.action;
    }

    final actionResult = await showActionSheet(
      context: context,
      body: l10n.doYouWantToDiscardTheEditsYouHaveMade,
      buttons: [
        ButtonWidget(
          labelText: l10n.yesDiscardChanges,
          buttonType: ButtonType.critical,
          shouldStickToDarkTheme: true,
          buttonAction: ButtonAction.first,
          isInAlert: true,
        ),
        ButtonWidget(
          labelText: l10n.cancel,
          buttonType: ButtonType.secondary,
          shouldStickToDarkTheme: true,
          buttonAction: ButtonAction.cancel,
          isInAlert: true,
        ),
      ],
      actionSheetType: ActionSheetType.defaultActionSheet,
    );
    return actionResult?.action;
  }
}

class _AvatarActionButton extends StatelessWidget {
  final double size;
  final bool isUnlink;
  final VoidCallback onTap;

  const _AvatarActionButton({
    required this.size,
    required this.isUnlink,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isUnlink ? colors.warning : colors.primary,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: HugeIcon(
            icon: isUnlink
                ? HugeIcons.strokeRoundedCancel01
                : HugeIcons.strokeRoundedEdit03,
            color: Colors.white,
            size: 12,
            strokeWidth: 2,
          ),
        ),
      ),
    );
  }
}

class _ContactThumbnailShell extends StatelessWidget {
  const _ContactThumbnailShell({
    required this.size,
    required this.child,
    this.backgroundColor,
  });

  final double size;
  final Widget child;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: FaceThumbnailSquircleClip(
        borderRadius: faceThumbnailSquircleBorderRadius(size),
        child: ColoredBox(
          color: backgroundColor ?? Colors.transparent,
          child: SizedBox.expand(child: child),
        ),
      ),
    );
  }
}

import "dart:async";
import "dart:typed_data";

import "package:ente_contacts/contacts.dart" as contacts;
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:figma_squircle/figma_squircle.dart";
import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:logging/logging.dart";
import "package:photos/core/constants.dart";
import "package:photos/db/files_db.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/models/search/search_constants.dart";
import "package:photos/module/download/thumbnail.dart";
import "package:photos/services/machine_learning/face_ml/face_filtering/face_filtering_constants.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/machine_learning/ml_result.dart";
import "package:photos/services/photos_contacts_service.dart";
import "package:photos/services/search_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/components/action_sheet_widget.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/menu_item_widget/menu_item_widget_new.dart";
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/people/face_thumbnail_squircle.dart";
import "package:photos/ui/viewer/people/person_face_widget.dart";
import "package:photos/ui/viewer/people/person_selection_action_widgets.dart";
import "package:photos/ui/viewer/search/result/contact_photo_adjust_page.dart";
import "package:photos/ui/viewer/search/result/contact_photo_picker_sheet.dart";
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/face/face_thumbnail_cache.dart";

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
  static const _maxThumbnailCompressionAttempts = 2;
  static const _avatarSize = 108.0;
  static const _editBadgeSize = 32.0;
  static const _avatarRadius = 20.0;
  static const _avatarCornerSmoothing = 0.6;

  final _logger = Logger("EditContactPage");
  late final TextEditingController _nameController;
  String? _selectedBirthDate;
  bool _isSaving = false;
  bool _isLoadingPhoto = false;
  bool _photoDirty = false;
  bool _resolvedAutofillPeople = false;
  Uint8List? _draftPhotoBytes;
  PersonEntity? _autofillPerson;
  List<PersonEntity> _autofillPreviewPeople = const [];
  int _photoLoadGeneration = 0;

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
    _selectedBirthDate = widget.existingContact?.data?.birthDate;
    _loadExistingPhoto();
    unawaited(_loadAutofillPeoplePreview());
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _canSave => !_isSaving && _nameController.text.trim().isNotEmpty;
  String get _initialName => (widget.existingContact?.data?.name ?? "").trim();
  String? get _initialBirthDate => widget.existingContact?.data?.birthDate;
  bool get _hasUnsavedChanges =>
      _nameController.text.trim() != _initialName ||
      _selectedBirthDate != _initialBirthDate ||
      _photoDirty;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
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
        backgroundColor: colorScheme.backgroundColour,
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: colorScheme.backgroundColour,
          surfaceTintColor: Colors.transparent,
          title: Text(
            l10n.editContact,
            style: textTheme.h3Bold.copyWith(fontSize: 20, height: 28 / 20),
          ),
          centerTitle: false,
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                children: [
                  Center(
                    child: SizedBox(
                      width: _avatarSize,
                      height: _avatarSize,
                      child: GestureDetector(
                        onTap: _pickContactPhoto,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            _buildAvatar(context, size: _avatarSize),
                            Positioned(
                              right: -4,
                              bottom: -4,
                              child: _AvatarEditButton(
                                size: _editBadgeSize,
                                onTap: _pickContactPhoto,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (_showAutofillRow) ...[
                    MenuItemWidgetNew(
                      title: l10n.autoFetchFromPeople,
                      subText: l10n.useTheirNameAndPhoto,
                      titleToSubTextSpacing: 4,
                      subTextStyle: textTheme.mini.copyWith(
                        color: colorScheme.textMuted,
                        height: 16 / 12,
                      ),
                      leadingIconSize: 44,
                      leadingIconWidget: _AutofillLeadingWidget(
                        person: _autofillPerson,
                        previewPeople: _autofillPreviewPeople,
                      ),
                      trailingIcon: Icons.chevron_right_rounded,
                      onTap: _autoFillFromPeople,
                    ),
                    const SizedBox(height: 28),
                  ],
                  _FieldLabel(text: l10n.email, isRequired: true),
                  const SizedBox(height: 8),
                  _InputShell(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      child: Text(widget.email, style: textTheme.body),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _FieldLabel(text: l10n.name),
                  const SizedBox(height: 8),
                  _InputShell(
                    child: TextField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      style: textTheme.body,
                      decoration: InputDecoration(
                        hintText: l10n.enterName,
                        hintStyle: textTheme.bodyFaint,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _FieldLabel(text: l10n.birthday),
                  const SizedBox(height: 8),
                  _BirthDateField(
                    value: _selectedBirthDate,
                    onTap: _pickBirthDate,
                    onClear: _selectedBirthDate == null
                        ? null
                        : () {
                            setState(() {
                              _selectedBirthDate = null;
                            });
                          },
                    hintText: l10n.enterDateOfBirthHint,
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: _SaveContactButton(
                  isDisabled: !_canSave,
                  onTap: _canSave ? _saveContact : null,
                ),
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
    final initial = trimmedName.isNotEmpty
        ? trimmedName.characters.first.toUpperCase()
        : widget.email.characters.first.toUpperCase();
    final avatarSeed = trimmedName.isNotEmpty ? trimmedName : widget.email;
    final avatarColor =
        colorScheme.avatarColors[avatarSeed.length.remainder(
          colorScheme.avatarColors.length,
        )];

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
      backgroundColor: avatarColor,
      child: Center(
        child: Text(
          initial,
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

  Future<void> _pickContactPhoto() async {
    final selectedFile = await showContactPhotoPickerSheet(context);
    if (selectedFile == null) {
      return;
    }
    setState(() {
      _isLoadingPhoto = true;
    });
    final sourceBytes = await _loadEditablePhotoBytesFromFile(selectedFile);
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
    final photoBytes = await _normalizeAttachmentBytes(croppedBytes);
    if (!mounted) {
      return;
    }
    setState(() {
      _draftPhotoBytes = photoBytes;
      _isLoadingPhoto = false;
      _photoDirty = photoBytes != null;
      _autofillPerson = null;
    });
  }

  Future<void> _autoFillFromPeople() async {
    final person = await routeToPage(
      context,
      const LinkContactToPersonSelectionPage(
        mode: PersonSelectionMode.autofillContact,
      ),
    );
    if (person is! PersonEntity || !mounted) {
      return;
    }
    _photoLoadGeneration++;
    _nameController.text = person.data.name;
    setState(() {
      _selectedBirthDate = person.data.birthDate;
      _autofillPerson = person;
      _isLoadingPhoto = true;
    });
    final photoBytes = await _buildAttachmentBytesFromPerson(person);
    if (!mounted) {
      return;
    }
    final shouldReloadExistingPhoto =
        photoBytes == null &&
        _draftPhotoBytes == null &&
        widget.existingContact?.profilePictureAttachmentId != null;
    setState(() {
      if (photoBytes != null) {
        _draftPhotoBytes = photoBytes;
        _photoDirty = true;
      }
      _isLoadingPhoto = false;
    });
    if (shouldReloadExistingPhoto) {
      unawaited(_loadExistingPhoto());
    }
  }

  Future<void> _saveContact() async {
    setState(() {
      _isSaving = true;
    });
    try {
      var saved = await PhotosContactsService.instance.createOrUpdateContact(
        contactUserId: widget.contactUserId,
        name: _nameController.text.trim(),
        birthDate: _selectedBirthDate,
      );
      if (_photoDirty && _draftPhotoBytes != null) {
        saved = await PhotosContactsService.instance.setProfilePicture(
          contactId: saved.id,
          bytes: _draftPhotoBytes!,
        );
      }
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

  Future<Uint8List?> _loadEditablePhotoBytesFromFile(EnteFile file) async {
    return getThumbnail(file);
  }

  Future<Uint8List?> _normalizeAttachmentBytes(Uint8List sourceBytes) async {
    var bytes = sourceBytes;
    var attempts = 0;
    while (bytes.length > thumbnailDataLimit &&
        attempts < _maxThumbnailCompressionAttempts) {
      bytes = await compressThumbnail(bytes);
      attempts++;
    }
    return bytes;
  }

  Future<Uint8List?> _buildAttachmentBytesFromPerson(
    PersonEntity person,
  ) async {
    try {
      final hiddenFileIds = await SearchService.instance.getHiddenFiles().then(
        (files) => files.map((file) => file.uploadedFileID).toSet(),
      );
      final faceIds = await MLDataDB.instance.getFaceIDsForPersonOrderedByScore(
        person.remoteID,
      );
      EnteFile? sourceFile;
      String? faceId = person.data.avatarFaceID;

      if (faceId != null) {
        final fileId = getFileIdFromFaceId<int>(faceId);
        if (!hiddenFileIds.contains(fileId)) {
          sourceFile = await FilesDB.instance.getAnyUploadedFile(fileId);
        }
      }

      if (sourceFile == null) {
        for (final candidateFaceId in faceIds) {
          final fileId = getFileIdFromFaceId<int>(candidateFaceId);
          if (hiddenFileIds.contains(fileId)) {
            continue;
          }
          sourceFile = await FilesDB.instance.getAnyUploadedFile(fileId);
          if (sourceFile != null) {
            faceId = candidateFaceId;
            break;
          }
        }
      }

      if (sourceFile == null || sourceFile.uploadedFileID == null) {
        return null;
      }

      final face = await MLDataDB.instance.getCoverFaceForPerson(
        recentFileID: sourceFile.uploadedFileID!,
        avatarFaceId: faceId,
        personID: person.remoteID,
      );
      if (face == null) {
        return null;
      }

      final crops = await getCachedFaceCrops(
        sourceFile,
        [face],
        useFullFile: true,
        personOrClusterID: person.remoteID,
        useTempCache: false,
      );
      final croppedBytes = crops?[face.faceID];
      if (croppedBytes == null) {
        return null;
      }
      return _normalizeAttachmentBytes(croppedBytes);
    } catch (e, s) {
      _logger.warning("Failed to build contact photo from person", e, s);
      return null;
    }
  }

  Future<void> _pickBirthDate() async {
    final locale = Localizations.localeOf(context);
    final lastDate = DateTime.now();
    final initialDate = _selectedBirthDate == null
        ? lastDate
        : DateTime.tryParse(_selectedBirthDate!) ?? lastDate;
    final picked = await showDatePicker(
      context: context,
      locale: locale,
      initialDate: initialDate.isAfter(lastDate) ? lastDate : initialDate,
      firstDate: DateTime(1900),
      lastDate: lastDate,
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _selectedBirthDate = picked.toIso8601String().split("T").first;
    });
  }

  bool get _showAutofillRow =>
      _autofillPerson != null ||
      (_resolvedAutofillPeople && _autofillPreviewPeople.isNotEmpty);

  Future<void> _loadAutofillPeoplePreview() async {
    try {
      final persons = await PersonService.instance.getPersons();
      final results = await SearchService.instance.getAllFace(
        null,
        minClusterSize: kMinimumClusterSizeAllFaces,
      );
      final resultsById = <String, GenericSearchResult>{};
      for (final result in results) {
        final personId = result.params[kPersonParamID] as String?;
        if (personId == null || personId.isEmpty) {
          continue;
        }
        resultsById[personId] = result;
      }

      final previewPeople = <PersonEntity>[];
      for (final person in persons) {
        if (person.data.isIgnored) {
          continue;
        }
        if (!resultsById.containsKey(person.remoteID)) {
          continue;
        }
        previewPeople.add(person);
        if (previewPeople.length == 3) {
          break;
        }
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _autofillPreviewPeople = previewPeople;
        _resolvedAutofillPeople = true;
      });
    } catch (e, s) {
      _logger.warning("Failed to load autofill people preview", e, s);
      if (!mounted) {
        return;
      }
      setState(() {
        _autofillPreviewPeople = const [];
        _resolvedAutofillPeople = true;
      });
    }
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final bool isRequired;

  const _FieldLabel({required this.text, this.isRequired = false});

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    final colorScheme = getEnteColorScheme(context);

    return RichText(
      text: TextSpan(
        style: textTheme.small.copyWith(fontWeight: FontWeight.w600),
        children: [
          TextSpan(text: text),
          if (isRequired)
            TextSpan(
              text: " *",
              style: textTheme.small.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.textBase,
              ),
            ),
        ],
      ),
    );
  }
}

class _InputShell extends StatelessWidget {
  final Widget child;

  const _InputShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final backgroundColor = EnteTheme.isDark(context)
        ? colorScheme.backgroundElevated2
        : Colors.white;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _BirthDateField extends StatelessWidget {
  final String? value;
  final String hintText;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _BirthDateField({
    required this.value,
    required this.onTap,
    required this.hintText,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    final parsedDate = value == null ? null : DateTime.tryParse(value!);
    final localeName = Localizations.localeOf(context).toLanguageTag();
    final formattedDate = parsedDate == null
        ? null
        : DateFormat.yMMMd(localeName).format(parsedDate);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: _InputShell(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  formattedDate ?? hintText,
                  style: formattedDate == null
                      ? textTheme.bodyFaint
                      : textTheme.body,
                ),
              ),
              if (onClear != null)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClear,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: getEnteColorScheme(context).textMuted,
                    ),
                  ),
                ),
              Icon(
                Icons.calendar_today_outlined,
                size: 18,
                color: getEnteColorScheme(context).textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarEditButton extends StatelessWidget {
  final double size;
  final VoidCallback onTap;

  const _AvatarEditButton({required this.size, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: getEnteColorScheme(context).greenBase,
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Icon(Icons.edit_outlined, color: Colors.white, size: 12),
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
      child: ClipSmoothRect(
        radius: SmoothBorderRadius(
          cornerRadius: _EditContactPageState._avatarRadius,
          cornerSmoothing: _EditContactPageState._avatarCornerSmoothing,
        ),
        child: ColoredBox(
          color: backgroundColor ?? Colors.transparent,
          child: SizedBox.expand(child: child),
        ),
      ),
    );
  }
}

class _AutofillLeadingWidget extends StatelessWidget {
  final PersonEntity? person;
  final List<PersonEntity> previewPeople;

  const _AutofillLeadingWidget({this.person, this.previewPeople = const []});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final selectedPerson = person;

    if (selectedPerson != null) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: FaceThumbnailSquircleClip(
              child: PersonFaceWidget(
                personId: selectedPerson.remoteID,
                useFullFile: false,
              ),
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.primary500,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Icon(
                Icons.edit_outlined,
                size: 10,
                color: Colors.white,
              ),
            ),
          ),
        ],
      );
    }

    Widget buildFace(double left, PersonEntity person) {
      return Positioned(
        left: left,
        top: 3,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          child: ClipOval(
            child: PersonFaceWidget(
              personId: person.remoteID,
              useFullFile: false,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: 44,
      height: 32,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final entry in previewPeople.take(3).indexed)
            buildFace(entry.$1 * 11.0, entry.$2),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.primary500,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Icon(
                Icons.edit_outlined,
                size: 10,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveContactButton extends StatelessWidget {
  const _SaveContactButton({required this.isDisabled, required this.onTap});

  final bool isDisabled;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final l10n = AppLocalizations.of(context);
    final backgroundColor = isDisabled
        ? colorScheme.fillFaint
        : colorScheme.primary500;
    final textColor = isDisabled
        ? colorScheme.textFaint
        : colorScheme.contentReverse;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isDisabled ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          height: 48,
          width: double.infinity,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: Text(
              l10n.saveContact,
              style: textTheme.small.copyWith(
                color: textColor,
                fontWeight: FontWeight.w500,
                height: 20 / 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

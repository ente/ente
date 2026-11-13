import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:locker/models/info/info_item.dart';
import 'package:locker/ui/pages/base_info_page.dart';

class EmergencyContactPage extends BaseInfoPage<EmergencyContactData> {
  const EmergencyContactPage({
    super.key,
    super.mode = InfoPageMode.edit,
    super.existingFile,
    super.onCancelWithoutSaving,
  });

  @override
  State<EmergencyContactPage> createState() => _EmergencyContactPageState();
}

class _EmergencyContactPageState
    extends BaseInfoPageState<EmergencyContactData, EmergencyContactPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _contactDetailsController =
      TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  String _initialName = '';
  String _initialContactDetails = '';
  String _initialNotes = '';

  @override
  void loadExistingData() {
    final data = currentData;
    _nameController.text = data?.name ?? '';
    _contactDetailsController.text = data?.contactDetails ?? '';
    _notesController.text = data?.notes ?? '';
    _initialName = _nameController.text;
    _initialContactDetails = _contactDetailsController.text;
    _initialNotes = _notesController.text;
  }

  @override
  void refreshUIWithCurrentData() {
    super.refreshUIWithCurrentData();
    loadExistingData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactDetailsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  String get pageTitle => context.strings.emergencyContact;

  @override
  String get submitButtonText => context.strings.save;

  @override
  InfoType get infoType => InfoType.emergencyContact;

  @override
  bool validateForm() {
    return _nameController.text.isNotEmpty &&
        _contactDetailsController.text.isNotEmpty;
  }

  @override
  bool get hasUnsavedChanges {
    return _nameController.text != _initialName ||
        _contactDetailsController.text != _initialContactDetails ||
        _notesController.text != _initialNotes;
  }

  @override
  EmergencyContactData createInfoData() {
    return EmergencyContactData(
      name: _nameController.text,
      contactDetails: _contactDetailsController.text,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
    );
  }

  @override
  List<Widget> buildFormFields() {
    return [
      TextInputComponent(
        label: context.strings.contactName,
        hintText: context.strings.contactNameHint,
        controller: _nameController,
        isRequired: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.next,
        onChanged: (_) => onFieldChanged(),
      ),
      const SizedBox(height: 24),
      TextInputComponent(
        label: context.strings.contactDetails,
        hintText: context.strings.contactDetailsHint,
        controller: _contactDetailsController,
        isRequired: true,
        textInputAction: TextInputAction.next,
        onChanged: (_) => onFieldChanged(),
      ),
      const SizedBox(height: 24),
      TextInputComponent(
        label: context.strings.contactNotes,
        hintText: context.strings.contactNotesHint,
        controller: _notesController,
        keyboardType: TextInputType.multiline,
        minLines: 3,
        maxLines: 12,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.newline,
      ),
    ];
  }

  @override
  List<Widget> buildViewFields() {
    return [
      buildViewField(
        label: context.strings.contactName,
        value: _nameController.text,
      ),
      const SizedBox(height: 24),
      buildViewField(
        label: context.strings.contactDetails,
        value: _contactDetailsController.text,
      ),
      if (_notesController.text.isNotEmpty) ...[
        const SizedBox(height: 24),
        buildViewField(
          label: context.strings.contactNotes,
          value: _notesController.text,
          maxLines: 3,
        ),
      ],
    ];
  }
}

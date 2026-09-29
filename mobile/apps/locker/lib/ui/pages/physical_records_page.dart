import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:locker/models/info/info_item.dart';
import 'package:locker/ui/pages/base_info_page.dart';

class PhysicalRecordsPage extends BaseInfoPage<PhysicalRecordData> {
  const PhysicalRecordsPage({
    super.key,
    super.mode = InfoPageMode.edit,
    super.existingFile,
    super.onCancelWithoutSaving,
  });

  @override
  State<PhysicalRecordsPage> createState() => _PhysicalRecordsPageState();
}

class _PhysicalRecordsPageState
    extends BaseInfoPageState<PhysicalRecordData, PhysicalRecordsPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  String _initialName = '';
  String _initialLocation = '';
  String _initialNotes = '';

  @override
  void loadExistingData() {
    final data = currentData;
    _nameController.text = data?.name ?? '';
    _locationController.text = data?.location ?? '';
    _notesController.text = data?.notes ?? '';
    _initialName = _nameController.text;
    _initialLocation = _locationController.text;
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
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  String get pageTitle {
    if (isInEditMode) {
      if (widget.existingFile != null || currentData != null) {
        return context.strings.editLocation;
      }
      return context.strings.physicalRecords;
    }

    final controllerName = _nameController.text.trim();
    if (controllerName.isNotEmpty) {
      return controllerName;
    }

    final dataName = (currentData?.name ?? '').trim();
    if (dataName.isNotEmpty) {
      return dataName;
    }

    return context.strings.physicalRecords;
  }

  @override
  String get submitButtonText => context.strings.save;

  @override
  InfoType get infoType => InfoType.physicalRecord;

  @override
  bool validateForm() {
    return _nameController.text.trim().isNotEmpty;
  }

  @override
  bool get hasUnsavedChanges {
    return _nameController.text.trim() != _initialName.trim() ||
        _locationController.text.trim() != _initialLocation.trim() ||
        _notesController.text.trim() != _initialNotes.trim();
  }

  @override
  PhysicalRecordData createInfoData() {
    return PhysicalRecordData(
      name: _nameController.text.trim(),
      location: _locationController.text.trim(),
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );
  }

  @override
  List<Widget> buildFormFields() {
    return [
      TextInputComponent(
        label: context.strings.name,
        hintText: context.strings.recordNameHint,
        controller: _nameController,
        isRequired: true,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.next,
        onChanged: (_) => onFieldChanged(),
      ),
      const SizedBox(height: 24),
      TextInputComponent(
        label: context.strings.recordLocation,
        hintText: context.strings.recordLocationHint,
        controller: _locationController,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.next,
        onChanged: (_) => onFieldChanged(),
      ),
      const SizedBox(height: 24),
      TextInputComponent(
        label: context.strings.recordNotes,
        hintText: context.strings.recordNotesHint,
        controller: _notesController,
        minLines: 3,
        maxLines: 12,
        textCapitalization: TextCapitalization.sentences,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
      ),
    ];
  }

  @override
  List<Widget> buildViewFields() {
    final fields = <Widget>[];

    if (_locationController.text.trim().isNotEmpty) {
      fields.add(
        buildViewField(
          label: context.strings.recordLocation,
          value: _locationController.text,
        ),
      );
    }

    if (_notesController.text.trim().isNotEmpty) {
      if (fields.isNotEmpty) fields.add(const SizedBox(height: 24));
      fields.add(
        buildViewField(
          label: context.strings.recordNotes,
          value: _notesController.text,
          maxLines: 6,
        ),
      );
    }

    return fields;
  }
}

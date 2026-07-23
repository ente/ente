import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:locker/l10n/l10n.dart';
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

  @override
  void initState() {
    super.initState();
    _loadExistingData();
  }

  void _loadExistingData() {
    final data = currentData;
    if (data != null) {
      _nameController.text = data.name;
      _locationController.text = data.location;
      _notesController.text = data.notes ?? '';
    }
  }

  @override
  void refreshUIWithCurrentData() {
    super.refreshUIWithCurrentData();
    _loadExistingData();
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
        return context.l10n.editLocation;
      }
      return context.l10n.physicalRecords;
    }

    final controllerName = _nameController.text.trim();
    if (controllerName.isNotEmpty) {
      return controllerName;
    }

    final dataName = (currentData?.name ?? '').trim();
    if (dataName.isNotEmpty) {
      return dataName;
    }

    return context.l10n.physicalRecords;
  }

  @override
  String get submitButtonText => context.l10n.saveRecord;

  @override
  InfoType get infoType => InfoType.physicalRecord;

  @override
  bool validateForm() {
    return _nameController.text.trim().isNotEmpty &&
        _locationController.text.trim().isNotEmpty;
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
        label: context.l10n.name,
        hintText: context.l10n.recordNameHint,
        controller: _nameController,
        isRequired: true,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.next,
        onChanged: (_) => onFieldChanged(),
      ),
      const SizedBox(height: 24),
      TextInputComponent(
        label: context.l10n.recordLocation,
        hintText: context.l10n.recordLocationHint,
        controller: _locationController,
        isRequired: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.next,
        onChanged: (_) => onFieldChanged(),
      ),
      const SizedBox(height: 24),
      TextInputComponent(
        label: context.l10n.recordNotes,
        hintText: context.l10n.recordNotesHint,
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
    final fields = <Widget>[
      buildViewField(
        label: context.l10n.recordLocation,
        value: _locationController.text,
      ),
    ];

    if (_notesController.text.trim().isNotEmpty) {
      fields.addAll([
        const SizedBox(height: 24),
        buildViewField(
          label: context.l10n.recordNotes,
          value: _notesController.text,
          maxLines: 6,
        ),
      ]);
    }

    return fields;
  }
}

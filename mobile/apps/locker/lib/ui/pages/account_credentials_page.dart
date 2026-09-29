import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:locker/models/info/info_item.dart';
import 'package:locker/ui/pages/base_info_page.dart';

class AccountCredentialsPage extends BaseInfoPage<AccountCredentialData> {
  const AccountCredentialsPage({
    super.key,
    super.mode = InfoPageMode.edit,
    super.existingFile,
    super.onCancelWithoutSaving,
  });

  @override
  State<AccountCredentialsPage> createState() => _AccountCredentialsPageState();
}

class _AccountCredentialsPageState
    extends BaseInfoPageState<AccountCredentialData, AccountCredentialsPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  String _initialName = '';
  String _initialUsername = '';
  String _initialPassword = '';
  String _initialNotes = '';

  @override
  void loadExistingData() {
    final data = currentData;
    _nameController.text = data?.name ?? '';
    _usernameController.text = data?.username ?? '';
    _passwordController.text = data?.password ?? '';
    _notesController.text = data?.notes ?? '';
    _initialName = _nameController.text;
    _initialUsername = _usernameController.text;
    _initialPassword = _passwordController.text;
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
    _usernameController.dispose();
    _passwordController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  String get pageTitle {
    if (isInEditMode) {
      if (widget.existingFile != null || currentData != null) {
        return context.strings.editSecret;
      }
      return context.strings.accountCredentials;
    }

    final controllerName = _nameController.text.trim();
    if (controllerName.isNotEmpty) {
      return controllerName;
    }

    final dataName = (currentData?.name ?? '').trim();
    if (dataName.isNotEmpty) {
      return dataName;
    }

    return context.strings.accountCredentials;
  }

  @override
  String get submitButtonText => context.strings.save;

  @override
  InfoType get infoType => InfoType.accountCredential;

  @override
  bool validateForm() {
    return _nameController.text.trim().isNotEmpty;
  }

  @override
  bool get hasUnsavedChanges {
    return _nameController.text.trim() != _initialName.trim() ||
        _usernameController.text.trim() != _initialUsername.trim() ||
        _passwordController.text.trim() != _initialPassword.trim() ||
        _notesController.text.trim() != _initialNotes.trim();
  }

  @override
  AccountCredentialData createInfoData() {
    return AccountCredentialData(
      name: _nameController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text.trim(),
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );
  }

  @override
  List<Widget> buildFormFields() {
    return [
      TextInputComponent(
        label: context.strings.credentialName,
        hintText: context.strings.credentialNameHint,
        controller: _nameController,
        isRequired: true,
        textCapitalization: TextCapitalization.sentences,
        autofocus: true,
        textInputAction: TextInputAction.next,
        onChanged: (_) => onFieldChanged(),
      ),
      const SizedBox(height: 24),
      TextInputComponent(
        label: context.strings.username,
        hintText: context.strings.usernameHint,
        controller: _usernameController,
        textInputAction: TextInputAction.next,
        onChanged: (_) => onFieldChanged(),
      ),
      const SizedBox(height: 24),
      TextInputComponent(
        label: context.strings.password,
        hintText: context.strings.passwordHint,
        controller: _passwordController,
        isPasswordInput: true,
        textInputAction: TextInputAction.next,
        onChanged: (_) => onFieldChanged(),
      ),
      const SizedBox(height: 24),
      TextInputComponent(
        label: context.strings.credentialNotes,
        hintText: context.strings.credentialNotesHint,
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
    final usernameText = _usernameController.text;
    final passwordText = _passwordController.text;
    final notesText = _notesController.text;

    final fields = <Widget>[];

    if (usernameText.trim().isNotEmpty) {
      fields.add(
        buildViewField(label: context.strings.username, value: usernameText),
      );
    }

    if (passwordText.trim().isNotEmpty) {
      if (fields.isNotEmpty) fields.add(const SizedBox(height: 24));
      fields.add(
        buildViewField(
          label: context.strings.password,
          value: passwordText,
          isSecret: true,
        ),
      );
    }

    if (notesText.trim().isNotEmpty) {
      if (fields.isNotEmpty) fields.add(const SizedBox(height: 24));
      fields.add(
        buildViewField(
          label: context.strings.credentialNotes,
          value: notesText,
          maxLines: 6,
        ),
      );
    }

    return fields;
  }
}

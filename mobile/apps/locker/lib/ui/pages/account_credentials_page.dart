import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:locker/l10n/l10n.dart';
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

  @override
  void initState() {
    super.initState();
    _loadExistingData();
  }

  void _loadExistingData() {
    final data = currentData;
    if (data != null) {
      _nameController.text = data.name;
      _usernameController.text = data.username;
      _passwordController.text = data.password;
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
    _usernameController.dispose();
    _passwordController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  String get pageTitle {
    if (isInEditMode) {
      if (widget.existingFile != null || currentData != null) {
        return context.l10n.editSecret;
      }
      return context.l10n.accountCredentials;
    }

    final controllerName = _nameController.text.trim();
    if (controllerName.isNotEmpty) {
      return controllerName;
    }

    final dataName = (currentData?.name ?? '').trim();
    if (dataName.isNotEmpty) {
      return dataName;
    }

    return context.l10n.accountCredentials;
  }

  @override
  String get submitButtonText => context.l10n.saveRecord;

  @override
  InfoType get infoType => InfoType.accountCredential;

  @override
  bool validateForm() {
    return _nameController.text.trim().isNotEmpty &&
        _usernameController.text.trim().isNotEmpty &&
        _passwordController.text.trim().isNotEmpty;
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
        label: context.l10n.credentialName,
        hintText: context.l10n.credentialNameHint,
        controller: _nameController,
        isRequired: true,
        textCapitalization: TextCapitalization.sentences,
        autofocus: true,
        textInputAction: TextInputAction.next,
        onChanged: (_) => onFieldChanged(),
      ),
      const SizedBox(height: 24),
      TextInputComponent(
        label: context.l10n.username,
        hintText: context.l10n.usernameHint,
        controller: _usernameController,
        isRequired: true,
        textInputAction: TextInputAction.next,
        onChanged: (_) => onFieldChanged(),
      ),
      const SizedBox(height: 24),
      TextInputComponent(
        label: context.l10n.password,
        hintText: context.l10n.passwordHint,
        controller: _passwordController,
        isRequired: true,
        isPasswordInput: true,
        textInputAction: TextInputAction.next,
        onChanged: (_) => onFieldChanged(),
      ),
      const SizedBox(height: 24),
      TextInputComponent(
        label: context.l10n.credentialNotes,
        hintText: context.l10n.credentialNotesHint,
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

    final fields = <Widget>[
      buildViewField(label: context.l10n.username, value: usernameText),
      const SizedBox(height: 24),
      buildViewField(
        label: context.l10n.password,
        value: passwordText,
        isSecret: true,
      ),
    ];

    if (notesText.trim().isNotEmpty) {
      fields.addAll([
        const SizedBox(height: 24),
        buildViewField(
          label: context.l10n.credentialNotes,
          value: notesText,
          maxLines: 6,
        ),
      ]);
    }

    return fields;
  }
}

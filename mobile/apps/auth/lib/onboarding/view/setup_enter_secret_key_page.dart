import 'dart:async';

import 'package:ente_auth/events/codes_updated_event.dart';
import "package:ente_auth/l10n/l10n.dart";
import 'package:ente_auth/models/all_icon_data.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/models/code_display.dart';
import 'package:ente_auth/store/code_display_store.dart';
import 'package:ente_auth/ui/components/buttons/button_widget.dart';
import 'package:ente_auth/ui/components/custom_icon_widget.dart';
import 'package:ente_auth/ui/components/models/button_result.dart';
import 'package:ente_auth/ui/custom_icon_page.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_page_scaffold.dart';
import 'package:ente_auth/ui/utils/icon_utils.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_auth/utils/toast_util.dart';
import 'package:ente_auth/utils/totp_util.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_events/event_bus.dart';
import "package:flutter/material.dart";
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

class SetupEnterSecretKeyPage extends StatefulWidget {
  static const manualCodeTextLimit = 200;

  final Code? code;

  SetupEnterSecretKeyPage({this.code, super.key});

  static int? manualCodeTextLimitFor(Code? code) {
    if (code == null ||
        (code.issuer.length < manualCodeTextLimit &&
            code.account.length < manualCodeTextLimit &&
            code.secret.length < manualCodeTextLimit)) {
      return manualCodeTextLimit;
    }
    return null;
  }

  @override
  State<SetupEnterSecretKeyPage> createState() =>
      _SetupEnterSecretKeyPageState();
}

class _SetupEnterSecretKeyPageState extends State<SetupEnterSecretKeyPage> {
  final Logger _logger = Logger('_SetupEnterSecretKeyPageState');
  final int _notesLimit = 500;
  final int defaultDigits = 6;
  final int defaultPeriodInSeconds = 30;
  late final int? _textLimit;
  late TextEditingController _issuerController;
  late TextEditingController _accountController;
  late TextEditingController _secretController;
  late TextEditingController _notesController;
  late TextEditingController _digitsController;
  late TextEditingController _periodController;
  late List<String> selectedTags = [...?widget.code?.display.tags];
  List<String> allTags = [];
  StreamSubscription<CodesUpdatedEvent>? _streamSubscription;
  bool isCustomIcon = false;
  String _customIconID = "";
  late IconType _iconSrc;
  late Algorithm _algorithm;
  late Type _type;
  final ValueNotifier<bool> showAdvancedOptions = ValueNotifier<bool>(false);

  @override
  void initState() {
    _textLimit = SetupEnterSecretKeyPage.manualCodeTextLimitFor(widget.code);
    _issuerController = TextEditingController(
      text: widget.code != null ? safeDecode(widget.code!.issuer).trim() : null,
    );
    _accountController = TextEditingController(
      text: widget.code != null
          ? safeDecode(widget.code!.account).trim()
          : null,
    );
    _secretController = TextEditingController(text: widget.code?.secret);
    _notesController = TextEditingController(text: widget.code?.display.note);
    _digitsController = TextEditingController(
      text: widget.code != null
          ? widget.code!.digits.toString()
          : defaultDigits.toString(),
    );
    _periodController = TextEditingController(
      text: widget.code != null
          ? widget.code!.period.toString()
          : defaultPeriodInSeconds.toString(),
    );

    _loadTags();
    _streamSubscription = Bus.instance.on<CodesUpdatedEvent>().listen((event) {
      _loadTags();
    });
    _notesController.addListener(() {
      if (_notesController.text.length > _notesLimit) {
        _notesController.text = _notesController.text.substring(0, _notesLimit);
        _notesController.selection = TextSelection.fromPosition(
          TextPosition(offset: _notesController.text.length),
        );
        showToast(context, context.l10n.notesLengthLimit(_notesLimit));
      }
    });

    isCustomIcon = widget.code?.display.isCustomIcon ?? false;
    if (isCustomIcon) {
      _customIconID = widget.code?.display.iconID ?? "ente";
    } else {
      if (widget.code != null) {
        _customIconID = widget.code!.issuer;
      }
    }
    _iconSrc = widget.code?.display.iconSrc == "simpleIcon"
        ? IconType.simpleIcon
        : IconType.customIcon;

    _algorithm = widget.code == null ? Algorithm.sha1 : widget.code!.algorithm;
    _type = widget.code == null ? Type.totp : widget.code!.type;

    super.initState();
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _issuerController.dispose();
    _accountController.dispose();
    _secretController.dispose();
    _notesController.dispose();
    _digitsController.dispose();
    _periodController.dispose();
    showAdvancedOptions.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    allTags = await CodeDisplayStore.instance.getAllTags();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AuthSettingsPageScaffold(
      title: l10n.importAccountPageTitle,
      children: [
        Semantics(
          identifier: 'auth_manual_code_page',
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.code != null) ...[
                    Semantics(
                      identifier: 'auth_manual_code_icon',
                      button: true,
                      label: l10n.appIcon,
                      child: Center(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(Radii.sheet),
                          onTap: navigateToCustomIconPage,
                          child: Padding(
                            padding: const EdgeInsets.all(Spacing.sm),
                            child: CustomIconWidget(iconData: _customIconID),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: Spacing.xl),
                  ],
                  Semantics(
                    identifier: 'auth_manual_issuer',
                    child: TextInputComponent(
                      controller: _issuerController,
                      label: l10n.codeIssuerHint,
                      isClearable: true,
                      maxLength: _textLimit,
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(height: Spacing.lg),
                  Semantics(
                    identifier: 'auth_manual_secret',
                    child: TextInputComponent(
                      controller: _secretController,
                      label: l10n.secret,
                      isRequired: true,
                      isPasswordInput: true,
                      maxLength: _textLimit,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(height: Spacing.lg),
                  Semantics(
                    identifier: 'auth_manual_account',
                    child: TextInputComponent(
                      controller: _accountController,
                      label: l10n.account,
                      isClearable: true,
                      maxLength: _textLimit,
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(height: Spacing.lg),
                  Semantics(
                    identifier: 'auth_manual_notes',
                    child: TextInputComponent(
                      controller: _notesController,
                      label: l10n.notes,
                      isClearable: true,
                      maxLength: _notesLimit,
                      minLines: 3,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                    ),
                  ),
                  const SizedBox(height: Spacing.xl),
                  _buildTags(context),
                  if (widget.code == null) ...[
                    const SizedBox(height: Spacing.xl),
                    _buildAdvancedOptions(context),
                  ],
                  const SizedBox(height: Spacing.xxl),
                  Semantics(
                    identifier: 'auth_manual_save',
                    child: ButtonComponent(
                      label: l10n.saveAction,
                      onTap: _validateAndSave,
                    ),
                  ),
                  const SizedBox(height: Spacing.xl),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTags(BuildContext context) {
    final colors = context.componentColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.tags,
          style: TextStyles.bodyBold.copyWith(color: colors.textBase),
        ),
        const SizedBox(height: Spacing.sm),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            for (final tag in allTags)
              TagChipComponent(
                label: tag,
                state: selectedTags.contains(tag)
                    ? TagChipComponentState.selected
                    : TagChipComponentState.unselected,
                onTap: () => _toggleTag(tag),
              ),
            Semantics(
              button: true,
              label: context.l10n.addTag,
              identifier: 'auth_manual_add_tag',
              child: TagChipComponent(
                label: context.l10n.addTag,
                leading: const Icon(Icons.add, size: IconSizes.small),
                onTap: _createTag,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _toggleTag(String tag) {
    setState(() {
      selectedTags.contains(tag)
          ? selectedTags.remove(tag)
          : selectedTags.add(tag);
    });
  }

  Future<void> _createTag() async {
    await showTextInputDialog(
      context,
      title: context.l10n.createNewTag,
      label: context.l10n.tag,
      submitButtonLabel: context.l10n.create,
      maxLength: 100,
      onSubmit: (value) async {
        final tag = value.trim();
        if (tag.isEmpty) return;
        if (!allTags.contains(tag)) allTags.add(tag);
        if (!selectedTags.contains(tag)) selectedTags.add(tag);
        if (mounted) setState(() {});
      },
    );
  }

  Widget _buildAdvancedOptions(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: showAdvancedOptions,
      builder: (context, isExpanded, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              label: context.l10n.advanced,
              identifier: 'auth_manual_advanced',
              child: MenuGroupComponent(
                items: [
                  MenuComponent(
                    title: context.l10n.advanced,
                    trailing: Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: IconSizes.medium,
                    ),
                    onTap: () => showAdvancedOptions.value = !isExpanded,
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              child: !isExpanded
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: Spacing.lg),
                      child: Column(
                        children: [
                          MenuGroupComponent(
                            showDividers: true,
                            dividerPadding: const EdgeInsets.only(
                              left: Spacing.lg,
                            ),
                            items: [
                              Semantics(
                                button: true,
                                label: context.l10n.algorithm,
                                identifier: 'auth_manual_algorithm',
                                child: MenuComponent(
                                  title: context.l10n.algorithm,
                                  subtitle: _algorithm.name.toUpperCase(),
                                  trailing: const Icon(
                                    Icons.chevron_right_outlined,
                                  ),
                                  onTap: _selectAlgorithm,
                                ),
                              ),
                              Semantics(
                                button: true,
                                label: context.l10n.type,
                                identifier: 'auth_manual_type',
                                child: MenuComponent(
                                  title: context.l10n.type,
                                  subtitle: _type.name.toUpperCase(),
                                  trailing: const Icon(
                                    Icons.chevron_right_outlined,
                                  ),
                                  onTap: _selectType,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: Spacing.lg),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Semantics(
                                  textField: true,
                                  identifier: 'auth_manual_period',
                                  child: TextInputComponent(
                                    controller: _periodController,
                                    label: context.l10n.period,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: Spacing.lg),
                              Expanded(
                                child: Semantics(
                                  textField: true,
                                  identifier: 'auth_manual_digits',
                                  child: TextInputComponent(
                                    controller: _digitsController,
                                    label: context.l10n.digits,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _selectAlgorithm() async {
    final selected = await _showOptionPicker<Algorithm>(
      title: context.l10n.algorithm,
      values: Algorithm.values,
      selected: _algorithm,
      labelFor: (value) => value.name.toUpperCase(),
    );
    if (selected != null && mounted) setState(() => _algorithm = selected);
  }

  Future<void> _selectType() async {
    final selected = await _showOptionPicker<Type>(
      title: context.l10n.type,
      values: Type.values,
      selected: _type,
      labelFor: (value) => value.name.toUpperCase(),
    );
    if (selected != null && mounted) setState(() => _type = selected);
  }

  Future<T?> _showOptionPicker<T>({
    required String title,
    required List<T> values,
    required T selected,
    required String Function(T value) labelFor,
  }) {
    return showBottomSheetComponent<T>(
      context: context,
      builder: (sheetContext) => BottomSheetComponent(
        title: title,
        closeTooltip: context.l10n.close,
        content: MenuGroupComponent(
          showDividers: true,
          items: [
            for (final value in values)
              MenuComponent(
                title: labelFor(value),
                selected: value == selected,
                trailing: RadioComponent(
                  selected: value == selected,
                  onChanged: (_) => Navigator.of(sheetContext).pop(value),
                ),
                onTap: () => Navigator.of(sheetContext).pop(value),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _validateAndSave() async {
    final digits = int.tryParse(_digitsController.text.trim());
    if (digits != null && (digits < 1 || digits > 10)) {
      _showIncorrectDetailsDialog(
        context,
        message: 'Digits must be between 1 and 10',
      );
      return;
    }

    final period = int.tryParse(_periodController.text.trim());
    if (period != null && (period < 10 || period > 60)) {
      _showIncorrectDetailsDialog(
        context,
        message: 'Period must be between 10 and 60 seconds',
      );
      return;
    }

    if ((_accountController.text.trim().isEmpty &&
            _issuerController.text.trim().isEmpty) ||
        _secretController.text.trim().isEmpty ||
        _digitsController.text.trim().isEmpty ||
        digits == null ||
        _periodController.text.trim().isEmpty ||
        period == null) {
      final String message;
      if (_secretController.text.trim().isEmpty) {
        message = context.l10n.secretCanNotBeEmpty;
      } else if (_digitsController.text.isEmpty) {
        message = 'Digits cannot be empty';
      } else if (digits == null) {
        message = 'Digits is not an integer';
      } else if (_periodController.text.isEmpty) {
        message = 'Period cannot be empty';
      } else if (period == null) {
        message = 'Period is not an integer';
      } else {
        message = context.l10n.bothIssuerAndAccountCanNotBeEmpty;
      }
      _showIncorrectDetailsDialog(context, message: message);
      return;
    }

    await _saveCode();
  }

  Future<void> _saveCode() async {
    try {
      if (!mounted) return;
      final account = _accountController.text.trim();
      final issuer = _issuerController.text.trim();
      final secret = _secretController.text.trim().replaceAll(' ', '');
      final notes = _notesController.text.trim();
      final digits = int.tryParse(_digitsController.text.trim());
      final period = int.tryParse(_periodController.text.trim());

      final isStreamCode =
          issuer.toLowerCase() == "steam" ||
          issuer.toLowerCase().contains('steampowered.com');
      final CodeDisplay display =
          widget.code?.display.copyWith(tags: selectedTags) ??
          CodeDisplay(tags: selectedTags);
      display.note = notes;
      if (widget.code != null) {
        if (widget.code!.display.iconID != _customIconID.toLowerCase()) {
          display.iconID = _customIconID.toLowerCase();
        } else if (widget.code!.issuer != issuer) {
          display.iconID = issuer.toLowerCase();
        }
      }

      display.iconSrc = _iconSrc == IconType.simpleIcon
          ? 'simpleIcon'
          : 'customIcon';

      if (widget.code != null && widget.code!.secret != secret) {
        ButtonResult? result = await showChoiceActionSheet(
          context,
          title: context.l10n.warning,
          body: context.l10n.confirmUpdatingkey,
          firstButtonLabel: context.l10n.yes,
          secondButtonAction: ButtonAction.cancel,
          secondButtonLabel: context.l10n.cancel,
        );
        if (result == null) return;
        if (result.action != ButtonAction.first) {
          return;
        }
      }

      final Code newCode = widget.code == null
          ? Code.fromAccountAndSecret(
              isStreamCode ? Type.steam : _type,
              account,
              issuer,
              secret,
              display,
              isStreamCode ? Code.steamDigits : digits!,
              algorithm: _algorithm,
              period: period!,
            )
          : widget.code!.copyWith(
              account: account,
              issuer: issuer,
              secret: secret,
              display: display,
              algorithm: _algorithm,
              digits: digits!,
              type: _type,
              period: period,
            );

      // Verify the validity of the code
      getOTP(newCode);
      if (!mounted) return;
      Navigator.of(context).pop(newCode);
    } catch (e, s) {
      _logger.severe("Error saving code", e, s);
      _showIncorrectDetailsDialog(context);
    }
  }

  void _showIncorrectDetailsDialog(BuildContext context, {String? message}) {
    showErrorDialog(
      context,
      context.l10n.incorrectDetails,
      message ?? context.l10n.pleaseVerifyDetails,
    );
  }

  Future<void> navigateToCustomIconPage() async {
    final allIcons = IconUtils.instance.getAllIcons();
    String currentIcon;
    if (widget.code!.display.isCustomIcon) {
      currentIcon = widget.code!.display.iconID;
    } else {
      currentIcon = widget.code!.issuer;
    }
    final AllIconData? newCustomIcon = await Navigator.of(context).push(
      MaterialPageRoute<AllIconData>(
        builder: (context) {
          return CustomIconPage(currentIcon: currentIcon, allIcons: allIcons);
        },
      ),
    );
    if (newCustomIcon == null || !mounted) return;
    setState(() {
      _customIconID = newCustomIcon.title;
      _iconSrc = newCustomIcon.type;
    });
  }
}
